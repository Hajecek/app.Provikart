//
//  OfflineView.swift
//  Provikart
//

import SwiftUI

struct OfflineView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Jste offline", systemImage: "wifi.slash")
        } description: {
            Text("Znovu se připojte k internetu.")
        }
    }
}

#Preview {
    OfflineView()
}
