//
//  LaunchView.swift
//  Provikart
//
//  Úvodní obrazovka: jen logo, které přejde na přihlášení.
//

import SwiftUI

enum ProvikartBrand {
    static let yellow = Color(red: 251 / 255, green: 191 / 255, blue: 79 / 255)
    static let ink = Color(red: 0.09, green: 0.08, blue: 0.06)
    static let paper = Color(red: 0.984, green: 0.969, blue: 0.937)
    static let night = Color(red: 0.07, green: 0.07, blue: 0.06)
}

struct LoginLogoFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 {
            value = next
        }
    }
}

struct LaunchView: View {
    var isHandingOff = false
    var targetFrame: CGRect = .zero
    var onFinish: (() -> Void)?

    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack {
                launchBackground
                    .opacity(isHandingOff ? 0 : 1)

                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: ProvikartBrand.ink.opacity(0.14), radius: 24, y: 14)
                    .scaleEffect(logoScale)
                    .blur(radius: appeared ? 0 : 8)
                    .opacity(appeared ? 1 : 0)
                    .position(logoCenter(in: proxy.size, origin: origin))
                    .accessibilityLabel("Provikart")
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) {
                appeared = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                onFinish?()
            }
        }
    }

    private var logoScale: CGFloat {
        if isHandingOff, targetFrame.width > 0 {
            return targetFrame.width / 112
        }
        return appeared ? 1 : 0.9
    }

    private func logoCenter(in size: CGSize, origin: CGPoint) -> CGPoint {
        guard isHandingOff, targetFrame.width > 0 else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        return CGPoint(x: targetFrame.midX - origin.x, y: targetFrame.midY - origin.y)
    }

    private var launchBackground: some View {
        ZStack {
            ProvikartBrand.yellow
            RadialGradient(
                colors: [
                    Color.white.opacity(0.38),
                    Color.white.opacity(0)
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 8,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LaunchView()
}
