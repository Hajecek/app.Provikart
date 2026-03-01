//
//  TabMenuView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

enum Tabs: Hashable {
    case home
    case calendar
    case add
    case problems
}

private struct OpenAddSheetKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var openAddSheet: (() -> Void)? {
        get { self[OpenAddSheetKey.self] }
        set { self[OpenAddSheetKey.self] = newValue }
    }
}

struct TabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @State var selectedTab: Tabs = .home
    @State private var showAddSheet = false
    @State private var showAddAIModeSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Domů", systemImage: "house", value: .home) {
                HomeView()
                    .environment(\.openAddSheet, { showAddSheet = true })
            }

            Tab("Kalendář", systemImage: "calendar", value: .calendar) {
                CalendarView()
                    .environment(\.openAddSheet, { showAddSheet = true })
            }

            Tab("Problémy", systemImage: "exclamationmark.triangle", value: .problems) {
                ProblemsView()
                    .environment(\.openAddSheet, { showAddSheet = true })
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTypeSheetView(
                isPresented: $showAddSheet,
                onSelectAIMode: { showAddSheet = false; showAddAIModeSheet = true }
            )
        }
        .fullScreenCover(isPresented: $showAddAIModeSheet) {
            AddView(
                selectedTab: Binding(get: { .add }, set: { _ in showAddAIModeSheet = false }),
                isAIMode: .constant(true)
            )
            .environmentObject(authState)
        }
        .modifier(LoginApprovalBottomAccessoryModifier(approvalState: appLoginApprovalState))
    }
}

#Preview {
    TabMenuView()
        .environmentObject(AuthState())
        .environmentObject(AppLoginApprovalState())
}

