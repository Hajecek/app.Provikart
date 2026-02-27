//
//  ProblemyView.swift
//  Provikart
//

import SwiftUI

struct ProblemsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
            }
            .navigationTitle("Problémy")
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
    ProblemsView()
        .environmentObject(AuthState())
}
