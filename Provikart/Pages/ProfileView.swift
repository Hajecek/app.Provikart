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
            LargeTitleHeaderView(title: "Profil") {
                Color.orange.ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ProfileView()
}
