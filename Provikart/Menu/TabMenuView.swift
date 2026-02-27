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
    @State private var previousTab: Tabs = .home
    @State private var showAddSheet = false
    /// Když true, přepnutí na .add přišlo z výběru „AI objednávka“, ne z tapu na Plus – neotevíráme sheet.
    @State private var navigatingToAddFromSheet = false

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
                AddView(selectedTab: $selectedTab)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .add {
                if navigatingToAddFromSheet {
                    navigatingToAddFromSheet = false
                } else {
                    selectedTab = previousTab
                    showAddSheet = true
                }
            } else {
                previousTab = newValue
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTypeSheetView(
                isPresented: $showAddSheet,
                selectedTab: $selectedTab,
                navigatingToAddFromSheet: $navigatingToAddFromSheet
            )
        }
    }
}

#Preview {
    TabMenuView()
}

