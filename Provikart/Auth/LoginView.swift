//
//  LoginView.swift
//  Provikart
//
//  Přihlášení na klidném pozadí, bez dekorativního vzoru.
//

import SwiftUI

private enum LoginField: Hashable {
    case email, password
}

struct LoginView: View {
    var showsBrandLogo = true

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authState: AuthState
    @FocusState private var focusedField: LoginField?
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showUnsupportedRoleAlert = false

    private let authService = AuthService()

    private var showSessionExpiredBanner: Bool {
        guard let notice = authState.sessionExpiredNotice else { return false }
        return notice != AuthState.unsupportedRoleNoticeText
    }

    private var pageBackground: Color {
        colorScheme == .dark ? ProvikartBrand.night : ProvikartBrand.paper
    }

    private var fieldFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var buttonFill: Color {
        colorScheme == .dark ? ProvikartBrand.yellow : ProvikartBrand.ink
    }

    private var buttonLabel: Color {
        colorScheme == .dark ? ProvikartBrand.ink : .white
    }

    private var linkColor: Color {
        colorScheme == .dark ? ProvikartBrand.yellow : ProvikartBrand.ink
    }

    private func fieldStroke(isFocused: Bool) -> Color {
        if errorMessage != nil {
            return Color.red.opacity(0.8)
        }
        if isFocused {
            return colorScheme == .dark ? ProvikartBrand.yellow : ProvikartBrand.ink
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.1)
    }

    private func fieldLabelColor(isFocused: Bool) -> Color {
        if errorMessage != nil {
            return .red
        }
        return isFocused ? linkColor : .secondary
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 22) {
                            Spacer(minLength: 8)

                            VStack(spacing: 22) {
                                VStack(spacing: 8) {
                                    Image("logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 16, y: 8)
                                        .opacity(showsBrandLogo ? 1 : 0)
                                        .accessibilityLabel("Provikart")
                                        .accessibilityHidden(!showsBrandLogo)
                                        .background {
                                            GeometryReader { geo in
                                                Color.clear.preference(
                                                    key: LoginLogoFrameKey.self,
                                                    value: geo.frame(in: .global)
                                                )
                                            }
                                        }

                                    Text("Provikart")
                                        .font(.title2.bold())
                                        .foregroundStyle(.primary)
                                        .padding(.top, 6)

                                    Text("Přihlášení k účtu")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if showSessionExpiredBanner, let notice = authState.sessionExpiredNotice {
                                    sessionExpiredBanner(notice)
                                }

                                VStack(spacing: 16) {
                                    credentialField(
                                        title: "E-mail nebo uživatelské jméno",
                                        prompt: "např. jana@email.cz",
                                        icon: "envelope",
                                        field: .email,
                                        text: $email,
                                        isSecure: false
                                    )

                                    credentialField(
                                        title: "Heslo",
                                        prompt: "Zadejte heslo",
                                        icon: "lock",
                                        field: .password,
                                        text: $password,
                                        isSecure: true
                                    )
                                }
                                .animation(.easeOut(duration: 0.15), value: focusedField)
                                .animation(.easeOut(duration: 0.15), value: errorMessage)

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }

                                Button {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    performLogin()
                                } label: {
                                    ZStack {
                                        Text("Přihlásit se")
                                            .fontWeight(.semibold)
                                            .opacity(isLoading ? 0 : 1)
                                        if isLoading {
                                            ProgressView().tint(buttonLabel)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(buttonFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .foregroundStyle(buttonLabel)
                                }
                                .disabled(isLoading || email.isEmpty || password.isEmpty)
                                .opacity(isLoading || email.isEmpty || password.isEmpty ? 0.45 : 1)

                                orDivider

                                VStack(spacing: 10) {
                                    socialButton(title: "Přihlásit se přes Apple", kind: .apple)
                                    socialButton(title: "Přihlásit se přes Google", kind: .google)
                                }

                                VStack(spacing: 14) {
                                    HStack(spacing: 4) {
                                        Text("Nemáte účet?")
                                            .foregroundStyle(.secondary)
                                        NavigationLink {
                                            RegisterView()
                                        } label: {
                                            Text("Registrovat se")
                                                .fontWeight(.semibold)
                                                .foregroundStyle(linkColor)
                                        }
                                    }
                                    .font(.subheadline)

                                    Button {
                                        authState.setLoggedIn(true)
                                    } label: {
                                        Text("Pokračovat bez přihlášení")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            .frame(maxWidth: 360)
                            .frame(maxWidth: .infinity)

                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(minHeight: proxy.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Chybí oprávnění", isPresented: $showUnsupportedRoleAlert) {
                Button("OK", role: .cancel) {
                    authState.clearSessionExpiredNotice()
                }
            } message: {
                Text("Tomuto uživateli nebyla přidána oprávnění pro mobilní aplikaci.\n\nPokud si myslíte, že jde o chybu, kontaktujte administrátora.")
            }
            .onAppear {
                presentUnsupportedRoleAlertIfNeeded()
            }
            .onChange(of: authState.sessionExpiredNotice) { _, _ in
                presentUnsupportedRoleAlertIfNeeded()
            }
        }
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            Text("nebo")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func credentialField(
        title: String,
        prompt: String,
        icon: String,
        field: LoginField,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        let isFocused = focusedField == field
        let hasError = errorMessage != nil

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(fieldLabelColor(isFocused: isFocused))

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(hasError ? Color.red.opacity(0.85) : (isFocused ? linkColor : Color.secondary))
                    .frame(width: 22)

                Group {
                    if isSecure && !isPasswordVisible {
                        SecureField("", text: text, prompt: Text(prompt).foregroundStyle(.tertiary))
                    } else {
                        TextField("", text: text, prompt: Text(prompt).foregroundStyle(.tertiary))
                    }
                }
                .textContentType(isSecure ? .password : .username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .submitLabel(isSecure ? .go : .next)
                .onSubmit {
                    if isSecure {
                        performLogin()
                    } else {
                        focusedField = .password
                    }
                }

                if !isSecure && !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Smazat text")
                }

                if isSecure {
                    Button {
                        isPasswordVisible.toggle()
                        focusedField = .password
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Skrýt heslo" : "Zobrazit heslo")
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(fieldStroke(isFocused: isFocused), lineWidth: isFocused || hasError ? 1.5 : 1)
            )
        }
    }

    /// Apple a Google jsou zatím jen vzhled. Napojení přijde později.
    private func socialButton(title: String, kind: SocialLoginKind) -> some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                socialMark(kind)
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(socialForeground(kind))
            .background(socialBackground(kind), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(socialBorder(kind), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.48)
        .accessibilityHint("Zatím nedostupné")
    }

    @ViewBuilder
    private func socialMark(_ kind: SocialLoginKind) -> some View {
        switch kind {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 18, weight: .medium))
        case .google:
            GoogleMark()
        }
    }

    private func socialBackground(_ kind: SocialLoginKind) -> Color {
        switch kind {
        case .apple:
            return colorScheme == .dark ? .white : ProvikartBrand.ink
        case .google:
            return colorScheme == .dark ? Color.white.opacity(0.06) : .white
        }
    }

    private func socialForeground(_ kind: SocialLoginKind) -> Color {
        switch kind {
        case .apple:
            return colorScheme == .dark ? ProvikartBrand.ink : .white
        case .google:
            return .primary
        }
    }

    private func socialBorder(_ kind: SocialLoginKind) -> Color {
        switch kind {
        case .apple:
            return .clear
        case .google:
            return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12)
        }
    }

    private func sessionExpiredBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.body)
                .foregroundStyle(linkColor)
                .padding(.top, 1)
            Text(notice)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel(notice)
    }

    private func presentUnsupportedRoleAlertIfNeeded() {
        guard authState.sessionExpiredNotice == AuthState.unsupportedRoleNoticeText else { return }
        showUnsupportedRoleAlert = true
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
                    if response.user == nil {
                        print("[Login] Uživatel: (API nevrátilo objekt user)")
                    }
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    if case .unsupportedRole = error {
                        showUnsupportedRoleAlert = true
                        print("[Login] Nepodporovaná role")
                    } else {
                        errorMessage = error.localizedDescription
                        print("[Login] Chyba: \(error.localizedDescription)")
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

private enum SocialLoginKind {
    case apple, google
}

/// Zjednodušená značka Google pro tlačítko, které se teprve napojí.
private struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let line = side * 0.22
            let radius = side * 0.36
            let blue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
            let red = Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255)
            let yellow = Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)
            let green = Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)

            func stroke(_ start: Double, _ end: Double, _ color: Color) {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end),
                    clockwise: false
                )
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .butt))
            }

            stroke(-12, 48, blue)
            stroke(48, 145, green)
            stroke(145, 225, yellow)
            stroke(225, 292, red)

            let outer = radius + line / 2
            let clip = Path(
                ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)
            )
            let bar = Path(
                CGRect(
                    x: center.x - line * 0.08,
                    y: center.y - line * 0.43,
                    width: outer + line,
                    height: line * 0.86
                )
            )
            context.fill(bar.intersection(clip), with: .color(blue))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthState())
}
