//
//  SettingsView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        NavigationStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .bottom) {
                    Button("Odhlásit") {
                        authState.logOut()
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.bottom, 32)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeaderBar(title: "Nastavení")
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthState())
}
