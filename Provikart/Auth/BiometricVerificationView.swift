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

    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: biometricIconName)
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Ověření totožnosti")
                    .font(.title2.bold())

                Text("Pro pokračování ověřte svou totožnost")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    authenticate()
                } label: {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isAuthenticating ? "Čekám…" : "Ověřit totožnost")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .disabled(isAuthenticating)
            }
            .padding()
        }
        .onAppear {
            authenticate()
        }
    }

    private var biometricIconName: String {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            default: return "lock.shield"
            }
        }
        return "lock.shield"
    }

    private func authenticate() {
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
                    onSuccess()
                } else {
                    if let authError = authError as? LAError, authError.code == .userCancel {
                        errorMessage = nil
                    } else {
                        errorMessage = authError?.localizedDescription ?? "Ověření se nezdařilo. Zkuste to znovu."
                    }
                }
            }
        }
    }
}

#Preview {
    BiometricVerificationView(onSuccess: {})
}
