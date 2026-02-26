//
//  ContentView.swift
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

struct ContentView: View {
    @State var selectedTab: Tabs = .home
    @State var searchString = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                Color.green.ignoresSafeArea()
            }
            
            Tab("Profile", systemImage: "person", value: .profile) {
                Color.orange.ignoresSafeArea()
            }
            
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                Color.blue.ignoresSafeArea()
            }
            
            Tab(value: .search, role: .search) {
                NavigationStack {
                    List {
                        Text("Search screen")
                    }
                    .navigationTitle("Search")
                    .searchable(text: $searchString)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
