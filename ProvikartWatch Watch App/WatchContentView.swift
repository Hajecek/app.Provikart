//
//  WatchContentView.swift
//  ProvikartWatch Watch App
//
//  Hlavní obrazovka hodinek – provize za aktuální měsíc.
//

import SwiftUI

struct WatchContentView: View {
    @ObservedObject var sessionManager: WatchSessionManager

    @State private var commission: WatchCommissionResponse?
    @State private var commissionGoal: Double?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var servicesCount: Int?
    @State private var isLoadingServices = false
    @State private var servicesError: String?

    private let service = WatchCommissionService()
    private let goalsService = WatchUserGoalsService()
    private let orderItemsCountService = WatchOrderItemsCountService()

    private var effectiveCommissionGoal: Double {
        commissionGoal ?? 100_000
    }

    var body: some View {
        if !sessionManager.isAuthenticated {
            notAuthenticatedView
        } else {
            TabView {
                commissionView
                    .tag(0)
                servicesCountView
                    .tag(1)
            }
            .tabViewStyle(.page)
        }
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Přihlaste se přes iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Commission View

    private var commissionView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if isLoading && commission == nil {
                    ProgressView()
                        .scaleEffect(1.1)
                } else if let c = commission {
                    commissionDisplay(c)
                } else if let err = errorMessage {
                    errorView(err)
                } else {
                    ProgressView()
                        .scaleEffect(1.1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Provize")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    profileImage
                }
            }
        }
        .task {
            await loadCommission()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await loadCommission()
            }
        }
        .onChange(of: sessionManager.authToken) { _, _ in
            Task { await loadCommission() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchCommissionDidUpdate)) { notification in
            guard let info = notification.userInfo else { return }
            let value = info["commission"] as? Double ?? 0
            let currency = info["currency"] as? String ?? "Kč"
            let label = info["monthLabel"] as? String
            let goal = info["commissionGoal"] as? Double
            withAnimation(.easeInOut(duration: 0.3)) {
                commission = WatchCommissionResponse(
                    success: true,
                    month: "",
                    month_label: label,
                    commission: value,
                    currency: currency
                )
                if let goal { commissionGoal = goal }
            }
        }
    }

    // MARK: - Services Count View (druhá stránka – potáhni doleva)

    private var servicesCountView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if isLoadingServices && servicesCount == nil {
                    ProgressView()
                        .scaleEffect(1.1)
                } else if let count = servicesCount {
                    Text("\(count)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())

                    Text(count == 1 ? "služba" : count >= 2 && count <= 4 ? "služby" : "služeb")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else if let err = servicesError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Zkusit znovu") {
                        Task { await loadServicesCount() }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                } else {
                    ProgressView()
                        .scaleEffect(1.1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Služby")
        }
        .task {
            await loadServicesCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchServicesCountDidUpdate)) { notification in
            guard let info = notification.userInfo, let count = info["count"] as? Int else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                servicesCount = count
            }
        }
    }

    private func loadServicesCount() async {
        guard let token = sessionManager.authToken, !token.isEmpty else {
            servicesError = "Nejste přihlášeni"
            return
        }

        if servicesCount == nil { isLoadingServices = true }
        servicesError = nil

        do {
            let count = try await orderItemsCountService.fetchCount(token: token)
            withAnimation(.easeInOut(duration: 0.3)) {
                servicesCount = count
            }
        } catch {
            if servicesCount == nil {
                servicesError = error.localizedDescription
            }
        }

        isLoadingServices = false
    }

    // MARK: - Profile Image (toolbar)

    private var profileImage: some View {
        Group {
            if let url = sessionManager.profileImageURL {
                WatchProfileImageView(
                    url: url,
                    token: sessionManager.authToken,
                    size: 28
                )
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Commission Display

    private func commissionDisplay(_ c: WatchCommissionResponse) -> some View {
        VStack(spacing: 10) {
            commissionBarGraph(value: c.commission)

            if let label = c.month_label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatCommission(c.commission))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                Text(c.currency)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bar Graph

    private let barCount = 25
    private let barSpacing: CGFloat = 2
    @State private var animatedProgress: Double = 0

    private func commissionBarGraph(value: Double) -> some View {
        let targetProgress = min(value / effectiveCommissionGoal, 1.0)

        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let barProgress = Double(index + 1) / Double(barCount)
                    let isFilled = barProgress <= animatedProgress
                    let barHeight = barHeightFor(index: index)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isFilled ? barColor(forIndex: index) : Color.white.opacity(0.15))
                        .frame(height: barHeight)
                }
            }
            .frame(height: 32)

            HStack {
                Text("0")
                Spacer()
                Text(scaleLabel(effectiveCommissionGoal / 2))
                Spacer()
                Text(scaleLabel(effectiveCommissionGoal))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = targetProgress
            }
        }
        .onChange(of: value) { _, newValue in
            let newTarget = min(newValue / effectiveCommissionGoal, 1.0)
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedProgress = newTarget
            }
        }
    }

    private func scaleLabel(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000.0
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    private func barHeightFor(index: Int) -> CGFloat {
        let mid = barCount / 2
        let distFromCenter = abs(index - mid)
        let maxH: CGFloat = 32
        let minH: CGFloat = 14
        let factor = 1.0 - (Double(distFromCenter) / Double(mid)) * 0.5
        return minH + (maxH - minH) * factor
    }

    /// Tři barvy: od začátku oranžová, pak žlutá, ke konci zelená.
    private func barColor(forIndex index: Int) -> Color {
        let ratio = Double(index) / Double(barCount - 1)
        if ratio < 1.0 / 3.0 {
            return .orange
        } else if ratio < 2.0 / 3.0 {
            return .yellow
        } else {
            return .green
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Zkusit znovu") {
                Task { await loadCommission() }
            }
            .font(.caption2)
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Data

    private func loadCommission() async {
        guard let token = sessionManager.authToken, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni"
            return
        }

        if commission == nil { isLoading = true }
        errorMessage = nil

        do {
            let response = try await service.fetchCommission(token: token)
            let (goal, _) = (try? await goalsService.fetchGoals(token: token)) ?? (nil, nil)
            withAnimation(.easeInOut(duration: 0.3)) {
                commission = response
                if let goal { commissionGoal = goal }
            }
            saveCommissionToAppGroup(response, commissionGoal: goal)
        } catch {
            if commission == nil {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func saveCommissionToAppGroup(_ c: WatchCommissionResponse, commissionGoal: Double? = nil) {
        guard let suite = UserDefaults(suiteName: "group.com.hajecek.provikartApp") else { return }
        suite.set(NSNumber(value: c.commission), forKey: "widget_commission")
        suite.set(c.currency, forKey: "widget_currency")
        suite.set(c.month_label, forKey: "widget_month_label")
        suite.set(Date(), forKey: "widget_last_updated")
        if let goal = commissionGoal {
            suite.set(NSNumber(value: goal), forKey: "widget_commission_goal")
        } else {
            suite.removeObject(forKey: "widget_commission_goal")
        }
    }
}

#Preview {
    WatchContentView(sessionManager: WatchSessionManager.shared)
}
