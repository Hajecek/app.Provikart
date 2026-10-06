//
//  TabMenuView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI
import UIKit

enum Tabs: Hashable {
    case home
    case localities
    case add
    case orders
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
    @ViewBuilder
    var body: some View {
        switch authState.currentRole {
        case .manager:
            ManagerTabMenuView()
                .environmentObject(authState)
                .environmentObject(appLoginApprovalState)
        case .user:
            EmployeeTabMenuView()
                .environmentObject(authState)
                .environmentObject(appLoginApprovalState)
        case .unknown:
            // Nemělo by nastat – nepodporované role se odmítají při přihlášení.
            UnsupportedRoleView()
                .environmentObject(authState)
        }
    }
}

struct EmployeeTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @State var selectedTab: Tabs = .home
    @State private var showAddSheet = false
    @State private var showAddAIModeSheet = false
    @State private var showReportIssue = false
    @State private var showLocation = false
    @StateObject private var rdPhotoShortcut = RdPhotoShortcut()

    private let menuGold = UIColor(red: 0.969, green: 0.737, blue: 0.329, alpha: 1)

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Domů", systemImage: "house", value: .home) {
                HomeView()
                    .environment(\.openAddSheet, { showAddSheet = true })
            }

            Tab("Lokality", systemImage: "building.2", value: .localities) {
                NavigationStack {
                    UserSalesLocalitiesView()
                        .environmentObject(authState)
                        .environment(\.openAddSheet, { showAddSheet = true })
                }
            }

            Tab("Přidat", systemImage: "plus", value: .add, role: .search) {
                Color.clear
            }

            Tab("Objednávky", systemImage: "doc.text.magnifyingglass", value: .orders) {
                OrdersView()
                    .environment(\.openAddSheet, { showAddSheet = true })
            }

            Tab("Problémy", systemImage: "exclamationmark.bubble", value: .problems) {
                ProblemsView()
                    .environment(\.openAddSheet, { showAddSheet = true })
            }
        }
        .background(TabMenuSelectionColor(color: menuGold))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLocation = true
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .accessibilityLabel("Nahlásit lokalitu")
            }
        }
        .onAppear {
            LuckyChestController.shared.prepareIfNeeded()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .add {
                showAddSheet = true
                selectedTab = oldValue
            }
        }
        .sheet(isPresented: $showLocation) {
            UserLocationUpdateView()
                .environmentObject(authState)
        }
        .sheet(isPresented: $showAddSheet) {
            AddTypeSheetView(
                isPresented: $showAddSheet,
                onSelectAIMode: { showAddSheet = false; showAddAIModeSheet = true },
                onSelectReportProblem: { showAddSheet = false; showReportIssue = true }
            )
        }
        .fullScreenCover(isPresented: $showReportIssue) {
            ReportIssueView(isPresented: $showReportIssue)
                .environmentObject(authState)
        }
        .fullScreenCover(isPresented: $showAddAIModeSheet) {
            AddView(
                selectedTab: Binding(
                    get: { selectedTab },
                    set: { newValue in
                        showAddAIModeSheet = false
                        selectedTab = newValue
                    }
                ),
                isAIMode: .constant(true)
            )
            .environmentObject(authState)
        }
        .environmentObject(rdPhotoShortcut)
        .modifier(LoginApprovalBottomAccessoryModifier(
            approvalState: appLoginApprovalState,
            showsPhoto: selectedTab == .localities && rdPhotoShortcut.localityId != nil,
            photoEnabled: rdPhotoShortcut.canAdd,
            onTakePhoto: { rdPhotoShortcut.requestCamera() }
        ))
    }
}

/// Vybraná položka ve spodním menu má barvu aplikace. Oddělené plus si nechává systémovou barvu.
struct TabMenuSelectionColor: UIViewRepresentable {
    var color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let root = uiView.window?.rootViewController else { return }
            paint(root)
        }
    }

    private func paint(_ vc: UIViewController) {
        if let tab = vc as? UITabBarController {
            let appearance = tab.tabBar.standardAppearance
            for layout in [
                appearance.stackedLayoutAppearance,
                appearance.inlineLayoutAppearance,
                appearance.compactInlineLayoutAppearance,
            ] {
                layout.selected.iconColor = color
                layout.selected.titleTextAttributes = [.foregroundColor: color]
            }
            tab.tabBar.standardAppearance = appearance
            tab.tabBar.scrollEdgeAppearance = appearance
        }
        vc.children.forEach(paint)
    }
}

#Preview {
    TabMenuView()
        .environmentObject(AuthState())
        .environmentObject(AppLoginApprovalState())
}

private struct UnsupportedRoleView: View {
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        ContentUnavailableView {
            Label("Chybí oprávnění", systemImage: "lock.shield")
        } description: {
            Text(AuthState.unsupportedRoleNoticeText)
        } actions: {
            Button("Odhlásit se") {
                authState.logOut()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
