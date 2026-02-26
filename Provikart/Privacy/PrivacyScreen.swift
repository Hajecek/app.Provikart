//
//  PrivacyScreen.swift
//  Provikart
//
//  Zobrazeno při přechodu aplikace do pozadí – skryje obsah (např. v app switcheru).
//

import SwiftUI

struct PrivacyScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("Provikart")
                    .font(.title2.bold())
                    .foregroundStyle(.primary.opacity(0.9))

                Text("Obsah skryt z důvodu soukromí")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    PrivacyScreen()
        .preferredColorScheme(.light)
}
