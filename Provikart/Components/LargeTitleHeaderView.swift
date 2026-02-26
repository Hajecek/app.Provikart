//
//  LargeTitleHeaderView.swift
//  Provikart
//

import SwiftUI

struct LargeTitleHeaderView<Content: View>: View {
    let title: String
    var onProfileTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
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
