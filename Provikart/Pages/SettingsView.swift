//
//  SettingsView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            LargeTitleHeaderView(title: "Nastavení") {
                Color.blue.ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    SettingsView()
}
