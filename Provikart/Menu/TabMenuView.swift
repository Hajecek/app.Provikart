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
    case search
}

struct TabMenuView: View {
    @State var selectedTab: Tabs = .home
    @State var searchString = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
            }
            
            Tab("Profile", systemImage: "person", value: .profile) {
                ProfileView()
            }
            
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
            
            Tab(value: .search, role: .search) {
                SearchView(searchString: $searchString)
            }
        }
    }
}

#Preview {
    TabMenuView()
}
