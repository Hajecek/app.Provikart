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

struct TabMenuView: View {
    @State var selectedTab: Tabs = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Domů", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("Kalendář", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }

            Tab("Problémy", systemImage: "exclamationmark.triangle", value: .problems) {
                ProblemsView()
            }

            Tab("Přidat", systemImage: "plus", value: .add) {
                AddView()
            }
        }
    }
}

#Preview {
    TabMenuView()
}

