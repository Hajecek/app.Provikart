//
//  BiometricVerificationView.swift
//  Provikart
//
//  Obrazovka biometrického ověření (Face ID / Touch ID) po návratu z pozadí.
//

import LocalAuthentication
import SwiftUI

struct BiometricVerificationView: View {
    var onSuccess: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authState: AuthState
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var isUnlockAnimating = false
    @State private var didReportSuccess = false
    @State private var autoAuthTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AnimatedStripeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    profileAvatar

                    Text("Hezký den, \(displayName)!")
                        .font(.system(size: 29, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 8)

                Spacer()
            }
        }
        .opacity(isUnlockAnimating ? 0 : 1)
        .scaleEffect(isUnlockAnimating ? 1.04 : 1)
        .blur(radius: isUnlockAnimating ? 7 : 0)
        .animation(.easeInOut(duration: 0.42), value: isUnlockAnimating)
        .onAppear {
            // Auto-ověření spouštíme až ve chvíli, kdy je scéna opravdu aktivní.
            scheduleAutomaticAuthentication(delay: 0.55)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                scheduleAutomaticAuthentication(delay: 0.2)
            }
        }
        .onDisappear {
            autoAuthTask?.cancel()
            autoAuthTask = nil
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let url = authState.currentUser?.profileImageURL {
            AuthenticatedProfileImageView(
                url: url,
                token: authState.authToken,
                size: 82
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.26), radius: 10, y: 5)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFill()
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 82, height: 82)
                .background(Color.white.opacity(0.16), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.26), radius: 10, y: 5)
        }
    }

    private var displayName: String {
        if let first = authState.currentUser?.firstname?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        if let name = authState.currentUser?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name.components(separatedBy: " ").first ?? name
        }
        if let username = authState.currentUser?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }
        return "uživateli"
    }

    private func authenticate() {
        guard !isAuthenticating, !didReportSuccess else { return }

        let context = LAContext()
        var biometricError: NSError?
        var passcodeError: NSError?
        errorMessage = nil

        let useBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError)
        let usePasscode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcodeError)

        guard useBiometrics || usePasscode else {
            errorMessage = "Ověření není k dispozici. V nastavení zařízení zapněte heslo nebo Face ID / Touch ID."
            return
        }

        isAuthenticating = true
        let reason = "Ověřte totožnost pro přístup do aplikace Provikart."
        let policy: LAPolicy = useBiometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    handleSuccessfulAuthentication()
                } else if let laError = authError as? LAError, laError.code == .notInteractive {
                    // UI ještě není plně interaktivní, zkusíme to znovu.
                    errorMessage = nil
                    scheduleAutomaticAuthentication(delay: 0.3)
                } else if let laError = authError as? LAError, laError.code == .userCancel {
                    // I po zrušení systémové výzvy držíme lockscreen, dokud ověření neproběhne.
                    errorMessage = nil
                    scheduleAutomaticAuthentication(delay: 0.6)
                } else {
                    errorMessage = authError?.localizedDescription ?? "Ověření se nezdařilo. Zkuste to znovu."
                    scheduleAutomaticAuthentication(delay: 0.75)
                }
            }
        }
    }

    private func handleSuccessfulAuthentication() {
        guard !didReportSuccess else { return }
        didReportSuccess = true
        autoAuthTask?.cancel()
        autoAuthTask = nil
        withAnimation(.easeInOut(duration: 0.42)) {
            isUnlockAnimating = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onSuccess()
        }
    }

    @MainActor
    private func scheduleAutomaticAuthentication(delay: TimeInterval) {
        guard !didReportSuccess else { return }
        autoAuthTask?.cancel()
        autoAuthTask = Task { @MainActor in
            let delayNs = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, scenePhase == .active, !didReportSuccess else { return }
            authenticate()
        }
    }
}

private struct AnimatedStripeBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let background = Path(CGRect(origin: .zero, size: size))
                context.fill(background, with: .color(Color(red: 0.04, green: 0.05, blue: 0.08)))

                drawStripeCluster(
                    in: context,
                    size: size,
                    center: CGPoint(
                        x: size.width * 0.12 + CGFloat(sin(t * 0.27)) * 26,
                        y: size.height * 0.32 + CGFloat(cos(t * 0.20)) * 20
                    ),
                    baseRadius: min(size.width, size.height) * 0.14,
                    rings: 22,
                    tint: Color.white.opacity(0.14),
                    time: t,
                    rotationBase: .degrees(-18),
                    rotationSwing: .degrees(11),
                    directionalDrift: CGPoint(x: 20, y: -14),
                    phaseOffset: 0
                )

                drawStripeCluster(
                    in: context,
                    size: size,
                    center: CGPoint(
                        x: size.width * 0.88 + CGFloat(cos(t * 0.23)) * 18,
                        y: size.height * 0.75 + CGFloat(sin(t * 0.21)) * 16
                    ),
                    baseRadius: min(size.width, size.height) * 0.10,
                    rings: 17,
                    tint: Color.white.opacity(0.10),
                    time: t,
                    rotationBase: .degrees(162),
                    rotationSwing: .degrees(14),
                    directionalDrift: CGPoint(x: -18, y: 13),
                    phaseOffset: 1.15
                )

                drawStripeCluster(
                    in: context,
                    size: size,
                    center: CGPoint(
                        x: size.width * 0.60 + CGFloat(cos(t * 0.16)) * 12,
                        y: size.height * 0.08 + CGFloat(sin(t * 0.25)) * 10
                    ),
                    baseRadius: min(size.width, size.height) * 0.08,
                    rings: 13,
                    tint: Color.white.opacity(0.08),
                    time: t,
                    rotationBase: .degrees(74),
                    rotationSwing: .degrees(10),
                    directionalDrift: CGPoint(x: 12, y: 22),
                    phaseOffset: 2.4
                )

                context.addFilter(.colorMultiply(.black.opacity(0.42)))
                context.fill(background, with: .color(.black.opacity(0.32)))
            }
        }
    }

    private func drawStripeCluster(
        in context: GraphicsContext,
        size: CGSize,
        center: CGPoint,
        baseRadius: CGFloat,
        rings: Int,
        tint: Color,
        time: TimeInterval,
        rotationBase: Angle,
        rotationSwing: Angle,
        directionalDrift: CGPoint,
        phaseOffset: Double
    ) {
        for index in 0..<rings {
            let step = CGFloat(index)
            let phase = time + phaseOffset
            let wobble = CGFloat(sin(phase * 1.05 + Double(index) * 0.55)) * 6
            let radius = baseRadius + step * 21 + wobble
            let travel = CGFloat(sin(phase * 0.58 + Double(index) * 0.33))
            let centerX = center.x + directionalDrift.x * travel
            let centerY = center.y + directionalDrift.y * travel
            let stretchX = 1.45 + CGFloat(sin(phase * 0.34 + Double(index) * 0.17)) * 0.24
            let stretchY = 0.88 + CGFloat(cos(phase * 0.40 + Double(index) * 0.13)) * 0.16

            let rect = CGRect(
                x: centerX - radius * stretchX,
                y: centerY - radius * stretchY,
                width: radius * stretchX * 2,
                height: radius * stretchY * 2
            )
            let dynamicRotation = rotationBase.radians
                + rotationSwing.radians * sin(phase * 0.22 + Double(index) * 0.09)
            var path = Path(ellipseIn: rect)
            let rotate = CGAffineTransform(
                translationX: centerX,
                y: centerY
            )
            .rotated(by: dynamicRotation)
            .translatedBy(x: -centerX, y: -centerY)
            path = path.applying(rotate)

            context.stroke(
                path,
                with: .color(tint.opacity(0.72 - Double(index) * 0.018)),
                lineWidth: 1.35
            )
        }
    }
}

#Preview {
    BiometricVerificationView(onSuccess: {})
        .environmentObject(AuthState())
}
