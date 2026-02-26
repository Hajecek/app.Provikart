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
            LargeTitleHeaderView(title: "Vyhledávání") {
                List {
                    Text("Search screen")
                }
                .searchable(text: $searchString)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    SearchView(searchString: .constant(""))
}
