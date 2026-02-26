//
//  LaunchView.swift
//  Provikart
//
//  Launch screen zobrazený při spuštění aplikace.
//

import SwiftUI

struct LaunchView: View {
    var onFinish: (() -> Void)?

    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var isTransitioning = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .opacity(isTransitioning ? 0 : 1)
            }
            .scaleEffect(isTransitioning ? 1.1 : 1)
            .opacity(isTransitioning ? 0 : 1)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isTransitioning = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onFinish?()
                }
            }
        }
    }
}

#Preview {
    LaunchView()
}
