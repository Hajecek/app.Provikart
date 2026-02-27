//
//  AddView.swift
//  Provikart
//

import SwiftUI

struct AddView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
            }
            .navigationTitle("Přidat")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
        }
    }
}

#Preview {
    AddView()
        .environmentObject(AuthState())
}
