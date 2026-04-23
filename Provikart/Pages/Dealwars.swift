//
//  Dealwars.swift
//  Provikart
//
//

import SwiftUI

struct DealwarsView: View {
    var body: some View {
        VStack {
            Text("Na tomto se momentálně pracuje")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Dealwars")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    DealwarsView()
}
