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
    @State private var biometricSymbol = "faceid"
    @State private var biometricLabel = "Face ID"
    @State private var autoAuthTask: Task<Void, Never>?

    private var pageBackground: Color {
        colorScheme == .dark ? ProvikartBrand.night : ProvikartBrand.paper
    }

    private var buttonFill: Color {
        colorScheme == .dark ? ProvikartBrand.yellow : ProvikartBrand.ink
    }

    private var buttonLabel: Color {
        colorScheme == .dark ? ProvikartBrand.ink : .white
    }

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 16, y: 8)
                    .accessibilityLabel("Provikart")

                VStack(spacing: 14) {
                    profileAvatar

                    if let displayName {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        authenticate()
                    } label: {
                        Label("Ověřit přes \(biometricLabel)", systemImage: biometricSymbol)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(buttonFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(buttonLabel)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticating || didReportSuccess)
                    .opacity(isAuthenticating || didReportSuccess ? 0.55 : 1)

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 320)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .opacity(isUnlockAnimating ? 0 : 1)
        .animation(.easeInOut(duration: 0.42), value: isUnlockAnimating)
        .onAppear {
            resolveBiometry()
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
                size: 120
            )
        } else {
            Text(initials)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? ProvikartBrand.ink : .white)
                .frame(width: 120, height: 120)
                .background(colorScheme == .dark ? ProvikartBrand.yellow : ProvikartBrand.ink, in: Circle())
        }
    }

    private var displayName: String? {
        if let first = authState.currentUser?.firstname?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        if let name = authState.currentUser?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name.components(separatedBy: " ").first ?? name
        }
        if let username = authState.currentUser?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }
        return nil
    }

    private var initials: String {
        let source = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "?" }
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

#Preview {
    BiometricVerificationView(onSuccess: {})
        .environmentObject(AuthState())
}
