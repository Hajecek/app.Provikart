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
            Color(uiColor: .systemBackground).ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeaderBar(title: "Domů")
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    HomeView()
}
