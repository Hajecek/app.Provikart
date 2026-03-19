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
    @State private var showReportIssue = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Problémy", systemImage: "exclamationmark.bubble", value: .problems) {
                ManagerProblemsView()
            }

            Tab("Přidat", systemImage: "plus", value: .add, role: .search) {
                Color.clear
            }

            Tab("Nastavení", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }

        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .add {
                showReportIssue = true
                selectedTab = oldValue
            }
        }
        .fullScreenCover(isPresented: $showReportIssue) {
            ReportIssueView(isPresented: $showReportIssue)
                .environmentObject(authState)
        }
        .modifier(LoginApprovalBottomAccessoryModifier(approvalState: appLoginApprovalState))
    }
}
