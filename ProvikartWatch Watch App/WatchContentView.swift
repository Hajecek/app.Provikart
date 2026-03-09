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
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = WatchCommissionService()

    var body: some View {
        if !sessionManager.isAuthenticated {
            notAuthenticatedView
        } else {
            commissionView
        }
    }

    // MARK: - Not Authenticated

    @State private var isRequestingToken = false

    private var notAuthenticatedView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.darkGray), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Přihlaste se\nna iPhonu")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button {
                    isRequestingToken = true
                    sessionManager.requestTokenFromPhone()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        isRequestingToken = false
                    }
                } label: {
                    if isRequestingToken {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRequestingToken)
            }
        }
        .task {
            while !Task.isCancelled && !sessionManager.isAuthenticated {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !sessionManager.isAuthenticated {
                    sessionManager.requestTokenFromPhone()
                }
            }
        }
    }

    // MARK: - Commission

    private var commissionView: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            if isLoading && commission == nil {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            } else if let c = commission {
                commissionDisplay(c)
            } else if let err = errorMessage {
                errorView(err)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
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
            withAnimation(.easeInOut(duration: 0.3)) {
                commission = WatchCommissionResponse(
                    success: true,
                    month: "",
                    month_label: label,
                    commission: value,
                    currency: currency
                )
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.45, blue: 0.95),
                Color(red: 0.05, green: 0.25, blue: 0.65)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func commissionDisplay(_ c: WatchCommissionResponse) -> some View {
        VStack(spacing: 6) {
            Spacer()

            Text(formatCommission(c.commission))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())

            Text(c.currency)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if let label = c.month_label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.yellow)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                Task { await loadCommission() }
            } label: {
                Text("Zkusit znovu")
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
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
            withAnimation(.easeInOut(duration: 0.3)) {
                commission = response
            }
            saveCommissionToAppGroup(response)
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

    private func saveCommissionToAppGroup(_ c: WatchCommissionResponse) {
        guard let suite = UserDefaults(suiteName: "group.com.hajecek.provikartApp") else { return }
        suite.set(NSNumber(value: c.commission), forKey: "widget_commission")
        suite.set(c.currency, forKey: "widget_currency")
        suite.set(c.month_label, forKey: "widget_month_label")
        suite.set(Date(), forKey: "widget_last_updated")
    }
}

#Preview {
    WatchContentView(sessionManager: WatchSessionManager.shared)
}
