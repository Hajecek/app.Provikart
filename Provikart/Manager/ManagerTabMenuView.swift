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
    case team
    case settings
}

struct ManagerTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @StateObject private var reportIssueSheet = ManagerReportIssueSheetState()
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
    }
}
