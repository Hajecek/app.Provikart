//
//  TabMenuView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

enum Tabs: Hashable {
    case home
    case profile
    case settings
    case add
}

struct TabMenuView: View {
    @State var selectedTab: Tabs = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Domů", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("Přidat", systemImage: "plus", value: .add) {
                AddView()
            }

            Tab("Profil", systemImage: "person", value: .profile) {
                ProfileView()
            }

            Tab("Nastavení", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    TabMenuView()
}
