//
//  BiometricVerificationView.swift
//  Provikart
//
//  Obrazovka biometrického ověření (Face ID / Touch ID) po návratu z pozadí.
//

import LocalAuthentication
import SwiftUI
import UIKit

struct BiometricVerificationView: View {
    var onSuccess: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authState: AuthState
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var isUnlockAnimating = false
    @State private var didReportSuccess = false
    @State private var appeared = false
    @State private var pulse = false
    @State private var biometricSymbol = "faceid"
    @State private var biometricLabel = "Face ID"
    @State private var autoAuthTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            UnlockAtmosphereBackground()

            VStack(spacing: 0) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(5)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    .accessibilityLabel("Provikart")
                    .padding(.top, 8)

                Spacer(minLength: 12)

                VStack(spacing: 28) {
                    avatarBlock

                    VStack(spacing: 8) {
                        Text(greetingText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(displayName)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                        Text(statusText)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)

                Spacer(minLength: 12)

                bottomActions
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }
            .safeAreaPadding(.top)
            .safeAreaPadding(.bottom)
        }
        .opacity(isUnlockAnimating ? 0 : 1)
        .scaleEffect(isUnlockAnimating ? 1.03 : 1)
        .blur(radius: isUnlockAnimating ? 8 : 0)
        .animation(.easeInOut(duration: 0.42), value: isUnlockAnimating)
        .onAppear {
            resolveBiometry()
            withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
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

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Dobré ráno" }
        if hour < 18 { return "Dobré odpoledne" }
        return "Dobrý večer"
    }

    private var statusText: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if isAuthenticating {
            return "Pokračujte pomocí \(biometricLabel)"
        }
        return "Odemkněte aplikaci přes \(biometricLabel)"
    }

    private var avatarBlock: some View {
        ZStack {
            Circle()
                .stroke(brandOrange.opacity(pulse ? 0.18 : 0.38), lineWidth: 1.5)
                .frame(width: 168, height: 168)
                .scaleEffect(pulse && isAuthenticating ? 1.08 : 1)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 136, height: 136)
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                }
                .shadow(color: brandOrange.opacity(0.22), radius: 24, y: 10)

            profileAvatar
                .offset(y: 0)

            Image(systemName: biometricSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(brandOrange.gradient, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: brandOrange.opacity(0.45), radius: 8, y: 3)
                .offset(x: 48, y: 48)
        }
        .frame(width: 176, height: 176)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let url = authState.currentUser?.profileImageURL {
            AuthenticatedProfileImageView(
                url: url,
                token: authState.authToken,
                size: 108
            )
        } else {
            Text(initials)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 108, height: 108)
                .background(brandOrange.gradient, in: Circle())
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 12) {
            Button {
                authenticate()
            } label: {
                Label("Odemknout", systemImage: biometricSymbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(brandOrange)
            .controlSize(.large)
            .disabled(isAuthenticating || didReportSuccess)

            Text("Provikart chrání přístup k citlivým datům.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
    }

    private var brandOrange: Color {
        Color(red: 0.88, green: 0.42, blue: 0.07)
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

    private var initials: String {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = source.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    private func resolveBiometry() {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        switch context.biometryType {
        case .touchID:
            biometricSymbol = "touchid"
            biometricLabel = "Touch ID"
        case .opticID:
            biometricSymbol = "opticid"
            biometricLabel = "Optic ID"
        default:
            biometricSymbol = "faceid"
            biometricLabel = "Face ID"
        }
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
                    errorMessage = nil
                    scheduleAutomaticAuthentication(delay: 0.3)
                } else if let laError = authError as? LAError, laError.code == .userCancel {
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

private struct UnlockAtmosphereBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private let deep = Color(red: 0.72, green: 0.28, blue: 0.04)
    private let orange = Color(red: 0.88, green: 0.42, blue: 0.07)
    private let gold = Color(red: 0.94, green: 0.62, blue: 0.18)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let dx = CGFloat(sin(t * 0.28)) * 0.06
            let dy = CGFloat(cos(t * 0.22)) * 0.05

            ZStack {
                Color(uiColor: colorScheme == .dark ? .systemBackground : .systemGroupedBackground)

                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                        .init(0.0, 0.48), .init(Float(0.50 + dx), Float(0.38 + dy)), .init(1.0, 0.52),
                        .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0)
                    ],
                    colors: meshColors
                )
                .opacity(colorScheme == .dark ? 0.88 : 0.62)
                .blur(radius: 18)

                RadialGradient(
                    colors: [
                        orange.opacity(colorScheme == .dark ? 0.28 : 0.18),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.18),
                    startRadius: 10,
                    endRadius: 280
                )

                LinearGradient(
                    colors: [
                        Color(uiColor: .systemBackground).opacity(0.05),
                        Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.55 : 0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }

    private var meshColors: [Color] {
        if colorScheme == .dark {
            return [
                deep, orange, gold,
                Color.black, orange.opacity(0.7), deep,
                Color(red: 0.07, green: 0.05, blue: 0.04), Color.black, gold.opacity(0.35)
            ]
        }
        return [
            gold.opacity(0.9), orange.opacity(0.55), Color.white,
            Color(red: 1.0, green: 0.94, blue: 0.86), gold.opacity(0.45), Color.white,
            Color(uiColor: .systemGroupedBackground), Color.white, orange.opacity(0.2)
        ]
    }
}

#Preview {
    BiometricVerificationView(onSuccess: {})
        .environmentObject(AuthState())
}
