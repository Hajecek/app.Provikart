//
//  PrivacyScreen.swift
//  Provikart
//
//  Zobrazeno při přechodu aplikace do pozadí – skryje obsah (např. v app switcheru).
//

import SwiftUI

struct PrivacyScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .light ? .white : Color(.systemBackground)
    }

    private var titleColor: Color {
        colorScheme == .light ? .black : .primary
    }

    private var subtitleColor: Color {
        colorScheme == .light ? Color.black.opacity(0.7) : .secondary
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("Provikart")
                    .font(.title2.bold())
                    .foregroundStyle(titleColor)

                Text("Obsah skryt z důvodu soukromí")
                    .font(.footnote)
                    .foregroundStyle(subtitleColor)
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
