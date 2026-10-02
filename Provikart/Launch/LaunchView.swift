//
//  LaunchView.swift
//  Provikart
//
//  Úvodní obrazovka ve stejných barvách jako přihlášení.
//

import SwiftUI

struct LaunchView: View {
    var onFinish: (() -> Void)?

    @State private var logoScale: CGFloat = 0.86
    @State private var contentOpacity: Double = 0
    @State private var isTransitioning = false

    private let brandBlue = Color(red: 0.027, green: 0.471, blue: 0.843)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image("background-login")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                    .scaleEffect(logoScale)

                Text("Provikart")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                ProgressView()
                    .controlSize(.regular)
                    .tint(brandBlue)
            }
            .opacity(contentOpacity)
            .opacity(isTransitioning ? 0 : 1)
            .scaleEffect(isTransitioning ? 1.04 : 1)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                logoScale = 1
                contentOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.35)) {
                    isTransitioning = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFinish?()
                }
            }
        }
    }
}

#Preview {
    LaunchView()
}
