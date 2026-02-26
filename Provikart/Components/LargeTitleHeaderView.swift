//
//  LargeTitleHeaderView.swift
//  Provikart
//

import SwiftUI

/// Vlastní hlavička: velký nadpis vlevo, ikona profilu vpravo, v jednom řádku (pro Domů, Vyhledávání, Nastavení).
struct PageHeaderBar: View {
    let title: String
    var onProfileTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer(minLength: 0)
            Button(action: { onProfileTap?() }) {
                Image(systemName: "person.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// Systémový toolbar s nadpisem a ikonou profilu (pouze pro stránku Profil).
struct LargeTitleHeaderView<Content: View>: View {
    let title: String
    var onProfileTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { onProfileTap?() }) {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
