//
//  SearchView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct SearchView: View {
    @Binding var searchString: String
    
    var body: some View {
        NavigationStack {
            List {
                Text("Search screen")
            }
            .searchable(text: $searchString)
            .toolbar(.hidden, for: .navigationBar)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeaderBar(title: "Vyhledávání")
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    SearchView(searchString: .constant(""))
}
