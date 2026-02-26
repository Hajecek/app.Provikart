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
                Color(uiColor: .systemBackground).ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ProfileView()
}
