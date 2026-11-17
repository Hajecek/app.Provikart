//
//  BiometricVerificationView.swift
//  Provikart
//
//  Obrazovka biometrického ověření (Face ID / Touch ID) po návratu z pozadí.
//  Zamykací obrazovka: avatar s animovaným prstencem, velké tlačítko
//  biometrie dole a záložní odemčení kódem zařízení. Přechod do aplikace
//  řídí ProvikartApp (zámek se rozplyne, aplikace se zaostří).
//

import LocalAuthentication
import SwiftUI
import UIKit

struct BiometricVerificationView: View {
    var onSuccess: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var authState: AuthState
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var didReportSuccess = false
    @State private var biometricSymbol = "faceid"
    @State private var biometricLabel = "Face ID"
    @State private var hasBiometrics = true
    @State private var autoAuthTask: Task<Void, Never>?
    @State private var appeared = false
    @State private var errorShake: CGFloat = 0

    private var isDark: Bool { colorScheme == .dark }
    private var pageBackground: Color { isDark ? ProvikartBrand.night : ProvikartBrand.paper }
    private var ink: Color { isDark ? .white : ProvikartBrand.ink }
    private let yellow = ProvikartBrand.yellow
    private let success = Color(red: 0.36, green: 0.78, blue: 0.42)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)

                Spacer(minLength: 24)

                identity

                Spacer(minLength: 24)

                actions
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 460)
        }
        .onAppear {
            resolveBiometry()
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { appeared = true }
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

    // MARK: - Pozadí

    private var background: some View {
        ZStack {
            pageBackground
            BreathingGlow(color: yellow, isDark: isDark, reduceMotion: reduceMotion)
        }
        .ignoresSafeArea()
    }

    // MARK: - Hlavička (logo)

    private var header: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Provikart")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(ink.opacity(0.08)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Provikart")
        }
        // Hlavička stojí pevně – jen se objeví, nikam nejezdí.
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Uživatel

    private var identity: some View {
        VStack(spacing: 18) {
            ZStack {
                ringTrack
                avatar
                    .scaleEffect(didReportSuccess ? 1.04 : 1)
                lockBadge
            }
            .frame(width: 156, height: 156)

            VStack(spacing: 6) {
                Text(displayName.map { "Vítej zpět, \($0)" } ?? "Vítej zpět")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: statusText)
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
    }

    private var statusText: String {
        if didReportSuccess { return "Odemčeno" }
        if isAuthenticating { return "Ověřuji…" }
        return "Aplikace je zamčená"
    }

    /// Prstenec kolem avataru: točí se při ověřování, zezelená po úspěchu.
    private var ringTrack: some View {
        ZStack {
            Circle()
                .stroke(ink.opacity(0.08), lineWidth: 4)

            if didReportSuccess {
                Circle()
                    .stroke(success, lineWidth: 4)
                    .transition(.opacity)
            } else {
                TimelineView(.animation(paused: reduceMotion || !isAuthenticating)) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360
                    Circle()
                        .trim(from: 0, to: isAuthenticating ? 0.32 : 1)
                        .stroke(
                            AngularGradient(
                                colors: [yellow.opacity(0), yellow, yellow],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(isAuthenticating ? angle : -90))
                        .opacity(isAuthenticating ? 1 : 0.85)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAuthenticating)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: didReportSuccess)
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Text(initials)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(ProvikartBrand.ink)
                .frame(width: 132, height: 132)
                .background(yellow.gradient, in: Circle())

            if let url = authState.currentUser?.profileImageURL {
                AuthenticatedProfileImageView(url: url, token: authState.authToken, size: 132)
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(Circle())
        .shadow(color: .black.opacity(isDark ? 0.45 : 0.14), radius: 20, y: 10)
    }

    private var lockBadge: some View {
        Image(systemName: didReportSuccess ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(didReportSuccess ? .white : ProvikartBrand.ink)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 38, height: 38)
            .background(didReportSuccess ? success : yellow, in: Circle())
            .overlay(Circle().strokeBorder(pageBackground, lineWidth: 3))
            .offset(x: 50, y: 50)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: didReportSuccess)
            .accessibilityHidden(true)
    }

    // MARK: - Akce

    private var actions: some View {
        VStack(spacing: 14) {
            if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .modifier(ShakeEffect(travel: errorShake))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                authenticate(allowPasscode: !hasBiometrics)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: biometricSymbol)
                        .font(.system(size: 24, weight: .medium))
                        .symbolEffect(.pulse, options: .repeating, isActive: isAuthenticating && !reduceMotion)
                    Text(hasBiometrics ? "Odemknout pomocí \(biometricLabel)" : "Odemknout")
                        .font(.headline)
                }
                .foregroundStyle(ProvikartBrand.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(yellow, in: Capsule())
                .shadow(color: yellow.opacity(isDark ? 0.25 : 0.45), radius: 18, y: 8)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isAuthenticating || didReportSuccess)
            .opacity(isAuthenticating || didReportSuccess ? 0.6 : 1)

            if hasBiometrics {
                Button {
                    authenticate(allowPasscode: true)
                } label: {
                    Text("Použít kód zařízení")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.75))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating || didReportSuccess)
            }
        }
        .frame(maxWidth: 360)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: errorMessage)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
    }

    // MARK: - Data

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

    // MARK: - Ověření

    private func resolveBiometry() {
        let context = LAContext()
        var error: NSError?
        hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if !hasBiometrics {
            _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        }
        switch context.biometryType {
        case .touchID:
            biometricSymbol = "touchid"
            biometricLabel = "Touch ID"
        case .opticID:
            biometricSymbol = "opticid"
            biometricLabel = "Optic ID"
        case .faceID:
            biometricSymbol = "faceid"
            biometricLabel = "Face ID"
        default:
            biometricSymbol = hasBiometrics ? "faceid" : "lock.fill"
            biometricLabel = "Face ID"
        }
    }

    private func authenticate(allowPasscode: Bool = false) {
        guard !isAuthenticating, !didReportSuccess else { return }

        let context = LAContext()
        var biometricError: NSError?
        var passcodeError: NSError?
        errorMessage = nil

        let useBiometrics = !allowPasscode
            && context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError)
        let usePasscode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcodeError)

        guard useBiometrics || usePasscode else {
            showError("Ověření není k dispozici. V nastavení zařízení zapněte heslo nebo Face ID / Touch ID.")
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
                } else if let laError = authError as? LAError, laError.code == .userFallback {
                    // „Zadat kód“ v systémovém dialogu → rovnou ověření kódem.
                    authenticate(allowPasscode: true)
                } else {
                    showError(authError?.localizedDescription ?? "Ověření se nezdařilo. Zkuste to znovu.")
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        guard !reduceMotion else { return }
        errorShake = 0
        withAnimation(.linear(duration: 0.4)) { errorShake = 1 }
    }

    private func handleSuccessfulAuthentication() {
        guard !didReportSuccess else { return }
        autoAuthTask?.cancel()
        autoAuthTask = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            didReportSuccess = true
            errorMessage = nil
        }
        // Krátce ukázat odemčený zámek (zelený prstenec), pak předat aplikaci,
        // která zámek plynule rozplyne a sama se zaostří.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
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

/// „Dýchající“ žlutá záře v pozadí. Vlastní view se vlastním stavem, aby se
/// nekonečná animace nepřenesla na zbytek obrazovky (dřív rozhoupala hlavičku).
private struct BreathingGlow: View {
    let color: Color
    let isDark: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0.5 : (sin(t * 2 * .pi / 6.4) + 1) / 2
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(isDark ? 0.30 : 0.42), color.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 260
                        )
                    )
                    .frame(width: 520, height: 520)
                    .scaleEffect(0.92 + 0.16 * phase)
                    .offset(y: -40)
                    .blur(radius: 10)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(isDark ? 0.10 : 0.16), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: 80 + 40 * phase, y: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Zatřesení chybovou hláškou.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(travel * .pi * 6) * 8 * (1 - travel)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Lehké promáčknutí tlačítka.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    BiometricVerificationView(onSuccess: {})
        .environmentObject(AuthState())
}
