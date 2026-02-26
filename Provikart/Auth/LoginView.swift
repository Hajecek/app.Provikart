//
//  LoginView.swift
//  Provikart
//
//  Moderní přihlašovací obrazovka v iOS stylu.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authState: AuthState
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private let authService = AuthService()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 20)
                    .frame(maxHeight: .infinity)

                VStack(spacing: 20) {
                    // Logo / Branding
                    Image(colorScheme == .dark ? "logo" : "logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.bottom, 6)

                    Text("Přihlášení")
                        .font(.largeTitle.bold())

                    // Form
                    VStack(spacing: 14) {
                        TextField("E-mail nebo uživatelské jméno", text: $email)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.default)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                        SecureField("Heslo", text: $password)
                            .textContentType(.password)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        performLogin()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            }
                            Text("Přihlásit se")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .opacity(isLoading || email.isEmpty || password.isEmpty ? 0.7 : 1)

                    // Linky
                    VStack(spacing: 8) {
                        Button("Zapomenuté heslo?") {
                            // TODO: reset hesla
                        }
                        .font(.footnote)

                        Button("Vytvořit nový účet") {
                            // TODO: registrace
                        }
                        .font(.footnote)
                    }
                    .padding(.bottom, 4)
                }

                Spacer(minLength: 20)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func performLogin() {
        print("[Login] Stisknuto Přihlásit se")
        guard !email.isEmpty, !password.isEmpty else {
            print("[Login] Přerušeno – prázdný e-mail nebo heslo")
            return
        }
        print("[Login] Přihlašovací údaj: \(email), odesílám požadavek na API…")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await authService.login(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    authState.setLoggedIn(true, user: response.user, token: response.token)
                    print("[Login] Úspěch – přihlášení dokončeno")
                    print("[Login] Token: \(response.token ?? "—")")
                    if let u = response.user {
                        print("[Login] Uživatel:")
                        print("  id: \(u.id ?? 0)")
                        print("  email: \(u.email ?? "—")")
                        print("  name: \(u.name ?? "—")")
                        print("  username: \(u.username ?? "—")")
                        print("  personal_number: \(u.personal_number ?? "—")")
                        print("  firstname: \(u.firstname ?? "—")")
                        print("  lastname: \(u.lastname ?? "—")")
                        print("  profile_image: \(u.profile_image ?? "—")")
                        print("  role: \(u.role ?? "—")")
                    } else {
                        print("[Login] Uživatel: (API nevrátilo objekt user)")
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    print("[Login] Chyba: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthState())
}
