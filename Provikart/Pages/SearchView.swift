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
            .navigationTitle("Search")
            .searchable(text: $searchString)
        }
    }
}

#Preview {
    SearchView(searchString: .constant(""))
}
