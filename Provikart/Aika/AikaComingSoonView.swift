//
//  AikaComingSoonView.swift
//  Provikart
//
//  Upoutávka Aiky pro obchodníky: trénink se zákazníkem teprve chystáme.
//

import SwiftUI

struct AikaComingSoonView: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 13 / 255, green: 16 / 255, blue: 48 / 255), Color(red: 5 / 255, green: 6 / 255, blue: 13 / 255)],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)
                AikaOrbView(training: true)
                    .frame(maxWidth: 360)
                Text("Na tohle zatím nemáš potřebná oprávnění. Pracujeme na tom, prosím o strpení 🙏🚧")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 238 / 255, green: 240 / 255, blue: 1))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.16)))
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Aika")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { AikaComingSoonView() }
}
