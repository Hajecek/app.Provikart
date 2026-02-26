//
//  ProfileView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct ProfileView: View {
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
            PageHeaderBar(title: "Profil")
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ProfileView()
}
