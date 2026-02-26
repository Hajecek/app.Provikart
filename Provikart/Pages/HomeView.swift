//
//  HomeView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            LargeTitleHeaderView(title: "Domů") {
                Color.green.ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    HomeView()
}
