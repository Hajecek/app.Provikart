//
//  AddView.swift
//  Provikart
//

import SwiftUI

struct AddView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeaderBar(title: "Přidat")
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    AddView()
}
