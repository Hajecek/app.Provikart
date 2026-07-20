//
//  ManagerTopArchGlow.swift
//  Provikart
//
//  Měkký brand glow nahoře u manažera – do úplného ztracena.
//  Animace až po biometrickém ověření.
//

import SwiftUI

/// Sdílené pozadí manažera: systemGrouped + glow shora.
struct ManagerScreenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            ManagerTopArchGlow()
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

/// Měkký oranžový přechod odshora do ztracena (rozmazaný, bez ostré hrany).
struct ManagerTopArchGlow: View {
    @Environment(\.sessionUnlocked) private var sessionUnlocked

    private let logoDeep = Color(red: 0.72, green: 0.28, blue: 0.04)
    private let logoOrange = Color(red: 0.88, green: 0.42, blue: 0.07)
    private let logoGold = Color(red: 0.94, green: 0.62, blue: 0.18)

    @State private var revealed = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 420

            ZStack(alignment: .top) {
                // Dlouhý, hustý fade – žádná „plocha čára“
                LinearGradient(
                    stops: [
                        .init(color: logoDeep.opacity(0.48), location: 0),
                        .init(color: logoDeep.opacity(0.36), location: 0.08),
                        .init(color: logoOrange.opacity(0.28), location: 0.18),
                        .init(color: logoOrange.opacity(0.18), location: 0.30),
                        .init(color: logoGold.opacity(0.12), location: 0.42),
                        .init(color: logoGold.opacity(0.07), location: 0.55),
                        .init(color: logoGold.opacity(0.035), location: 0.68),
                        .init(color: logoGold.opacity(0.015), location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Měkké jádro – rozplyne se do stran i dolů
                RadialGradient(
                    colors: [
                        logoDeep.opacity(0.32),
                        logoOrange.opacity(0.14),
                        logoGold.opacity(0.05),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: -0.05),
                    startRadius: 4,
                    endRadius: max(width, height) * 0.75
                )
            }
            .frame(width: width, height: height)
            // Silný blur = okraj zmizí do pozadí
            .blur(radius: 28)
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 1.06, anchor: .top)
            .frame(width: width, height: height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .onAppear {
            syncReveal(unlocked: sessionUnlocked)
        }
        .onChange(of: sessionUnlocked) { _, unlocked in
            syncReveal(unlocked: unlocked)
        }
    }

    private func syncReveal(unlocked: Bool) {
        if unlocked {
            guard !revealed else { return }
            withAnimation(.easeOut(duration: 1.1)) {
                revealed = true
            }
        } else {
            revealed = false
        }
    }
}
