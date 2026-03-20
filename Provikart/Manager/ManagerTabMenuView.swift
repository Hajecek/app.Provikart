//
//  ManagerTabMenuView.swift
//  Provikart
//
//  Role-specific tab menu pro manažera.
//

import SwiftUI

enum ManagerTabs: Hashable {
    case problems
    case add
    case settings
}

struct ManagerTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @State private var selectedTab: ManagerTabs = .problems

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Problémy", systemImage: "exclamationmark.bubble", value: .problems) {
                ManagerProblemsView()
                    .environmentObject(authState)
            }

            Tab("Přidat", systemImage: "plus", value: .add) {
                ManagerReportIssueView(
                    isPresented: .constant(true),
                    authState: authState,
                    isModalPresentation: false,
                    onClose: { selectedTab = .problems }
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
