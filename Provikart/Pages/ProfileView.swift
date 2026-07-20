//
//  ProfileView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingEdit = false
    @State private var showLogoutConfirm = false
    @State private var appeared = false

    private let brandDeep = Color(red: 0.62, green: 0.22, blue: 0.03)
    private let brandOrange = Color(red: 0.88, green: 0.42, blue: 0.07)
    private let brandGold = Color(red: 0.96, green: 0.68, blue: 0.22)
    private let userSlate = Color(red: 0.14, green: 0.18, blue: 0.24)
    private let userTeal = Color(red: 0.12, green: 0.42, blue: 0.48)

    private let avatarSize: CGFloat = 108
    private let avatarOverlap: CGFloat = 54

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroBand
                contentSheet
            }
        }
        .background(pageBackground)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                        .navigationTitle("Nastavení")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Nastavení")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isShowingEdit) {
            NavigationStack {
                EditProfilePlaceholderView(user: authState.currentUser)
                    .navigationTitle("Upravit profil")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Hotovo") { isShowingEdit = false }
                        }
                    }
            }
        }
        .alert("Opravdu se chcete odhlásit?", isPresented: $showLogoutConfirm) {
            Button("Zrušit", role: .cancel) { }
            Button("Odhlásit", role: .destructive) {
                authState.logOut()
            }
        } message: {
            Text("Budete odhlášeni z vašeho účtu.")
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    // MARK: - Hero

    private var heroBand: some View {
        ZStack(alignment: .bottom) {
            heroGradient
                .frame(height: 248)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 180, height: 180)
                        .blur(radius: 2)
                        .offset(x: 50, y: -30)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(brandGold.opacity(0.18))
                        .frame(width: 120, height: 120)
                        .blur(radius: 18)
                        .offset(x: -40, y: 40)
                }

            VStack(spacing: 10) {
                Text(roleLabel.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.78))

                Text(displayName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 28)

                if let subtitle = accountSubtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: avatarOverlap + 8)
            }
            .padding(.top, 88)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .overlay(alignment: .bottom) {
            avatarView(size: avatarSize)
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 5)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
                .scaleEffect(appeared ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)
                .offset(y: avatarOverlap)
                .accessibilityHidden(true)
                .contextMenu {
                    Button {
                        isShowingEdit = true
                    } label: {
                        Label("Upravit profil", systemImage: "pencil")
                    }
                }
        }
        .zIndex(1)
    }

    private var heroGradient: some View {
        LinearGradient(
            colors: isManagerRole
                ? [brandDeep, brandOrange, brandGold]
                : [userSlate, userTeal.opacity(0.92), Color(red: 0.28, green: 0.58, blue: 0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Content sheet

    private var contentSheet: some View {
        VStack(alignment: .leading, spacing: 28) {
            identityMeta
                .padding(.top, avatarOverlap + 18)

            factsBlock

            actionsBlock

            logoutBlock
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 20, y: -4)
            .ignoresSafeArea(edges: .bottom)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
    }

    private var identityMeta: some View {
        HStack(spacing: 12) {
            if let planLabel {
                metaChip(planLabel)
            }
            Button {
                isShowingEdit = true
            } label: {
                Text("Upravit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private var factsBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Údaje")

            VStack(spacing: 0) {
                factRow(title: "E‑mail", value: emailDisplay)
                thinRule
                factRow(title: "Osobní číslo", value: personalNumberDisplay)
                if let username = authState.currentUser?.username, !username.isEmpty {
                    thinRule
                    factRow(title: "Uživatelské jméno", value: "@\(username)")
                }
            }
        }
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Možnosti")

            VStack(spacing: 10) {
                NavigationLink {
                    SettingsView()
                        .navigationTitle("Nastavení")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    optionLabel(
                        title: "Nastavení",
                        detail: "Vzhled, oznámení, soukromí",
                        symbol: "slider.horizontal.3"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isShowingEdit = true
                } label: {
                    optionLabel(
                        title: "Upravit profil",
                        detail: "Jméno, kontakt a foto",
                        symbol: "person.text.rectangle"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var logoutBlock: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            Text("Odhlásit se")
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Pieces

    private var pageBackground: some View {
        ZStack {
            heroGradient.ignoresSafeArea()
            Color(uiColor: .systemBackground)
                .ignoresSafeArea(edges: .bottom)
                .padding(.top, 200)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private func factRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }

    private var thinRule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private func optionLabel(
        title: String,
        detail: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func avatarView(size: CGFloat) -> some View {
        Group {
            if let url = authState.currentUser?.profileImageURL {
                AuthenticatedProfileImageView(
                    url: url,
                    token: authState.authToken,
                    size: size
                )
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.25), accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                    }
            }
        }
    }

    // MARK: - Data

    private var isManagerRole: Bool {
        switch authState.currentRole {
        case .manager: return true
        case .user, .unknown:
            let raw = authState.currentUser?.role?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return raw == "manager" || raw == "admin"
        }
    }

    private var accent: Color {
        isManagerRole ? brandOrange : userTeal
    }

    private var roleLabel: String {
        let raw = authState.currentUser?.role?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch raw {
        case "manager": return "Manažer"
        case "admin": return "Administrátor"
        case "user", "employee": return "Uživatel"
        default:
            return isManagerRole ? "Manažer" : "Uživatel"
        }
    }

    private var planLabel: String? {
        guard let plan = authState.currentUser?.plan?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !plan.isEmpty
        else { return nil }

        switch plan {
        case "paid", "premium", "pro":
            return "Placený plán"
        case "free":
            return "Free plán"
        default:
            return plan.capitalized
        }
    }

    private var displayName: String {
        if let name = authState.currentUser?.name, !name.isEmpty {
            return name
        }
        let first = authState.currentUser?.firstname ?? ""
        let last = authState.currentUser?.lastname ?? ""
        let composed = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !composed.isEmpty { return composed }
        if let username = authState.currentUser?.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel"
    }

    private var accountSubtitle: String? {
        if let username = authState.currentUser?.username, !username.isEmpty,
           displayName != "@\(username)" {
            return "@\(username)"
        }
        return nil
    }

    private var initials: String {
        let parts = displayName
            .replacingOccurrences(of: "@", with: "")
            .split(separator: " ")
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        if !letters.isEmpty {
            return letters.uppercased()
        }
        return String(displayName.prefix(1)).uppercased()
    }

    private var emailDisplay: String {
        let email = authState.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "Neuvedeno" : email
    }

    private var personalNumberDisplay: String {
        if let pn = authState.currentUser?.personal_number, !pn.isEmpty {
            return pn
        }
        return "Nenastaveno"
    }
}

private struct EditProfilePlaceholderView: View {
    let user: UserInfo?

    var body: some View {
        Form {
            Section("Profil") {
                TextField("Jméno", text: .constant(user?.name ?? ""))
                TextField("Uživatelské jméno", text: .constant(user?.username ?? ""))
                TextField("E‑mail", text: .constant(user?.email ?? ""))
            }
            Section {
                Button("Uložit změny") {}
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthState())
    }
}
