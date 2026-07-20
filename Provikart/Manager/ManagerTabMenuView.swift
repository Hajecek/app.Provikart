//
//  ManagerTabMenuView.swift
//  Provikart
//
//  Role-specific tab menu pro manažera.
//

import SwiftUI

enum ManagerTabs: Hashable {
    case problems
    case attendance
    case performance
    case team
    case settings
}

@MainActor
final class ManagerPerformanceBadgeState: ObservableObject {
    @Published var todayServicesCount: Int = 0

    private let service = ManagerTeamPerformanceService()
    private var didLoad = false

    func refreshIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await refresh(token: token)
    }

    func refresh(token: String?) async {
        guard let token, !token.isEmpty else { return }
        let month = Self.monthFormatter.string(from: Date())
        do {
            let payload = try await service.fetchPerformance(token: token, month: month)
            todayServicesCount = payload.todayServicesCount
            didLoad = true
        } catch {
            // Badge necháme beze změny – detailní chyba se řeší na stránce Výkon.
        }
    }

    func update(todayServicesCount: Int) {
        self.todayServicesCount = todayServicesCount
        didLoad = true
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()
}

struct ManagerTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @StateObject private var reportIssueSheet = ManagerReportIssueSheetState()
    @StateObject private var performanceBadge = ManagerPerformanceBadgeState()
    @State private var selectedTab: ManagerTabs = .problems
    @State private var problemsRefreshToken = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Problémy", systemImage: "exclamationmark.bubble", value: .problems) {
                ManagerProblemsView(refreshToken: problemsRefreshToken)
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
            }

            Tab("Docházka", systemImage: "person.badge.clock", value: .attendance) {
                ManagerAttendanceView()
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
            }

            Tab("Výkon", systemImage: "chart.bar", value: .performance) {
                ManagerTeamPerformanceView()
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
                    .environmentObject(performanceBadge)
            }
            .badge(performanceBadge.todayServicesCount > 0 ? performanceBadge.todayServicesCount : 0)

            Tab("Tým", systemImage: "person.3", value: .team) {
                ManagerTeamProfilesView()
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
            }

            Tab("Nastavení", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(authState)
                }
            }

        }
        .sheet(isPresented: $reportIssueSheet.isPresented) {
            ManagerReportIssueView(
                isPresented: $reportIssueSheet.isPresented,
                authState: authState,
                isModalPresentation: true,
                onClose: {
                    reportIssueSheet.isPresented = false
                    problemsRefreshToken = UUID()
                }
            )
            .environmentObject(authState)
        }
        .modifier(LoginApprovalBottomAccessoryModifier(approvalState: appLoginApprovalState))
        .task {
            await performanceBadge.refreshIfNeeded(token: authState.authToken)
        }
    }
}
