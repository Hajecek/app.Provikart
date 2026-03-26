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
    case add
    case settings
}

struct ManagerTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @State private var selectedTab: ManagerTabs = .problems
    @State private var problemsRefreshToken = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Problémy", systemImage: "exclamationmark.bubble", value: .problems) {
                ManagerProblemsView(refreshToken: problemsRefreshToken)
                    .environmentObject(authState)
            }

            Tab("Docházka", systemImage: "person.badge.clock", value: .attendance) {
                ManagerAttendanceView()
                    .environmentObject(authState)
            }

            Tab("Přidat", systemImage: "plus", value: .add) {
                ManagerReportIssueView(
                    isPresented: .constant(true),
                    authState: authState,
                    isModalPresentation: false,
                    onClose: {
                        selectedTab = .problems
                        problemsRefreshToken = UUID()
                    }
                )
            }

            Tab("Nastavení", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(authState)
                }
            }

        }
        .modifier(LoginApprovalBottomAccessoryModifier(approvalState: appLoginApprovalState))
    }
}
