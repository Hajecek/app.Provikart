//
//  ProfileView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var isShowingEdit = false
    @State private var showLogoutConfirm = false

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section("Údaje") {
                LabeledContent("E‑mail", value: emailDisplay)
                LabeledContent("Osobní číslo", value: personalNumberDisplay)
                if let username = authState.currentUser?.username, !username.isEmpty {
                    LabeledContent("Uživatelské jméno", value: "@\(username)")
                }
                if let planLabel {
                    LabeledContent("Plán", value: planLabel)
                }
            }

            Section {
                if isManagerRole {
                    NavigationLink {
                        ManagerTeamProfilesView()
                            .environmentObject(authState)
                    } label: {
                        Label("Tým", systemImage: "person.3")
                    }
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Nastavení", systemImage: "gearshape")
                }

                Button {
                    isShowingEdit = true
                } label: {
                    Label("Upravit profil", systemImage: "pencil")
                }
            }

            Section {
                Button("Odhlásit se", role: .destructive) {
                    showLogoutConfirm = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingEdit) {
            NavigationStack {
                EditProfilePlaceholderView(user: authState.currentUser)
                    .navigationTitle("Upravit profil")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
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
    }

    private var header: some View {
        VStack(spacing: 12) {
            avatarView(size: 88)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let subtitle = accountSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(roleLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .contextMenu {
            Button {
                isShowingEdit = true
            } label: {
                Label("Upravit profil", systemImage: "pencil")
            }
        }
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
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.34, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .accessibilityHidden(true)
    }

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
