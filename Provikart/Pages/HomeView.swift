//
//  HomeView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet
    @State private var commission: CommissionResponse?
    @State private var commissionError: String?
    @State private var isLoadingCommission = false
    @State private var isCommissionHidden = WidgetDataStore.isCommissionHidden
    /// Počet položek po termínu instalace čekajících na dokončení. nil = nenačteno, 0 = žádné, >0 = zobrazit container.
    @State private var pendingCompletionCount: Int?

    private let commissionService = CommissionService()
    private let pendingCompletionService = OrderItemsPendingCompletionService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    commissionRow
                } header: {
                    Text("Provize")
                        .textCase(nil)
                }

                if (pendingCompletionCount ?? 0) > 0 {
                    Section {
                        NavigationLink {
                            PendingCompletionListView()
                                .environmentObject(authState)
                        } label: {
                            pendingCompletionRowContent
                        }
                    } header: {
                        Text("Čekající na dokončení")
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Domů")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            StatisticsView()
                                .environmentObject(authState)
                                .environment(\.openAddSheet, openAddSheet)
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        NavigationLink {
                            ProblemsView()
                                .environmentObject(authState)
                                .environment(\.openAddSheet, openAddSheet)
                        } label: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let openAddSheet {
                        Button {
                            openAddSheet()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await loadCommission()
            await loadPendingCompletion()
            // Periodické obnovení provize a nedokončených na pozadí (každých 5 s)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await loadCommission(silent: true)
                await loadPendingCompletion()
            }
        }
        .refreshable {
            await loadCommission()
            await loadPendingCompletion()
        }
    }

    // MARK: - Commission Row (iOS List style)

    private var commissionRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, alignment: .center)

                    Text("Aktuální měsíc")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCommissionHidden.toggle()
                        }
                        WidgetDataStore.setCommissionHidden(isCommissionHidden)
                    } label: {
                        Image(systemName: isCommissionHidden ? "eye.slash" : "eye")
                            .font(.body)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }

                Group {
                    if isLoadingCommission {
                        loadingSkeleton
                    } else if let err = commissionError {
                        errorRow(message: err)
                    } else if let c = commission {
                        valueRow(commission: c)
                    } else {
                        Text("Přihlaste se pro zobrazení provize.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let c = commission, !isCommissionHidden {
                    CommissionProgressBarView(value: c.commission, goal: 100_000)
                }

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(periodText)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityBannerLabel)
    }

    // MARK: - Pending completion row (zobrazí se jen když count > 0)

    private var pendingCompletionRowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(Color.orange)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text("Položky po termínu instalace")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(pendingCompletionCount ?? 0) nedokončených")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(pendingCompletionCount ?? 0)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pendingCompletionCount ?? 0) položek čeká na dokončení po termínu instalace")
    }

    private var periodText: String {
        if let c = commission, let label = c.month_label, !label.isEmpty {
            return "Období: \(label)"
        } else {
            return "Období: aktuální měsíc"
        }
    }

    private var accessibilityBannerLabel: String {
        if isLoadingCommission {
            return "Provize za aktuální měsíc, načítám"
        } else if let err = commissionError {
            return "Provize za aktuální měsíc, chyba: \(err)"
        } else if let c = commission {
            return "Provize za aktuální měsíc \(formatCommission(c.commission)) \(c.currency)"
        } else {
            return "Provize za aktuální měsíc"
        }
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color.primary.opacity(0.08),
                        Color.primary.opacity(0.16),
                        Color.primary.opacity(0.08)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 140, height: 18)
                .redacted(reason: .placeholder)
                .shimmer()

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 100, height: 12)
                .redacted(reason: .placeholder)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button {
                Task { await loadCommission() }
            } label: {
                Text("Zkusit znovu")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func valueRow(commission c: CommissionResponse) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(isCommissionHidden ? "– – – –" : formatCommission(c.commission))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())

            if !isCommissionHidden {
                Text(c.currency)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data Loading

    /// Načte provizi z API. Při `silent: true` se nespouští loading stav – vhodné pro periodické obnovení na pozadí.
    private func loadCommission(silent: Bool = false) async {
        let token = await MainActor.run { authState.authToken }
        guard let token else {
            await MainActor.run {
                commission = nil
                commissionError = "Pro zobrazení provize se přihlaste."
            }
            return
        }
        if !silent {
            await MainActor.run {
                isLoadingCommission = true
                commissionError = nil
                commission = nil
            }
        }

        do {
            let response = try await commissionService.fetchCommission(token: token)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    commission = response
                }
                isLoadingCommission = false
                WidgetDataStore.saveCommission(response.commission, currency: response.currency, monthLabel: response.month_label)
                PhoneSessionManager.shared.sendCommissionUpdate(commission: response.commission, currency: response.currency, monthLabel: response.month_label)
            }
        } catch {
            await MainActor.run {
                if !silent {
                    commissionError = error.localizedDescription
                }
                isLoadingCommission = false
            }
        }
    }

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Načte počet položek čekajících na dokončení. Při chybě nastaví 0 (container se nezobrazí).
    private func loadPendingCompletion() async {
        let token = await MainActor.run { authState.authToken }
        guard let token, !token.isEmpty else {
            await MainActor.run { pendingCompletionCount = nil }
            return
        }
        do {
            let count = try await pendingCompletionService.fetchPendingCount(token: token)
            await MainActor.run { pendingCompletionCount = count }
        } catch {
            await MainActor.run { pendingCompletionCount = 0 }
        }
    }
}

// Jednoduchý shimmer efekt pro skeleton (iOS 15+ fallback bez animace)
private extension View {
    @ViewBuilder
    func shimmer(active: Bool = true, duration: Double = 1.2) -> some View {
        if #available(iOS 15.0, *), active {
            self
                .overlay {
                    GeometryReader { proxy in
                        let size = proxy.size
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.6),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .rotationEffect(.degrees(20))
                            .offset(x: -size.width)
                            .frame(width: size.width * 1.5)
                            .mask(self)
                            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: UUID())
                    }
                }
        } else {
            self
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthState())
}
