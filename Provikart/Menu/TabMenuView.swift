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
    /// Zobrazit v AddView režim „AI objednávka“ (vložit text → rozpoznat → přidat do DB).
    @State private var addViewAIMode = false

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
                AddView(selectedTab: $selectedTab, isAIMode: $addViewAIMode)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .add {
                if navigatingToAddFromSheet {
                    addViewAIMode = true
                    navigatingToAddFromSheet = false
                } else {
                    selectedTab = previousTab
                    showAddSheet = true
                }
            } else {
                previousTab = newValue
                addViewAIMode = false
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

