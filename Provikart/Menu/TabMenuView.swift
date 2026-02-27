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

private struct OfflineIndicatorView: View {
    var body: some View {
        Label("Offline – bez připojení", systemImage: "wifi.slash")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct TabMenuView: View {
    @State var selectedTab: Tabs = .home
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    var body: some View {
        tabView
            .modifier(OfflineAccessoryModifier(isOffline: networkMonitor.isOffline))
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Domů", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("Kalendář", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }

            Tab("Přidat", systemImage: "plus", value: .add) {
                AddView()
            }
        }
    }
}

// MARK: - TabView bottom accessory (iOS 26+) nebo overlay (starší iOS)
private struct OfflineAccessoryModifier: ViewModifier {
    let isOffline: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .tabViewBottomAccessory {
                    Group {
                        if isOffline {
                            OfflineIndicatorView()
                        }
                    }
                }
        } else {
            content
                .overlay(alignment: .bottom) {
                    if isOffline {
                        OfflineIndicatorView()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.bar, in: Capsule())
                            .padding(.bottom, 56) // nad tab barem
                    }
                }
        }
    }
}

#Preview {
    TabMenuView()
        .environmentObject(NetworkMonitor())
}

