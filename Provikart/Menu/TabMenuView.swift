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
}

struct TabMenuView: View {
    @State var selectedTab: Tabs = .home
    @State private var showProfile = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Domů", systemImage: "house", value: .home) {
                HomeView(showProfile: $showProfile)
            }

            Tab("Kalendář", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }

            Tab("Přidat", systemImage: "plus", value: .add) {
                AddView()
            }
        }
        .tabViewBottomAccessory(isEnabled: showProfile) {
            HStack {
                Label("Profil", systemImage: "person.circle.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Zpět") {
                    showProfile = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    TabMenuView()
}

