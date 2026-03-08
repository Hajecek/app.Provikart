//
//  ProfileView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingSettings = false
    @State private var isShowingEdit = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                contactSection
                settingsLogoutSection
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isShowingEdit = true
                    } label: {
                        avatarInToolbar
                    }
                    .accessibilityLabel("Upravit profil")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Nastavení", systemImage: "gearshape")
                    }
                    .accessibilityLabel("Nastavení")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Domů", systemImage: "house.fill")
                    }
                    .accessibilityLabel("Zpět na Domů")
                    Spacer()
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Nastavení", systemImage: "gearshape")
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .background {
                NavigationLink(isActive: $isShowingSettings) {
                    SettingsView()
                        .navigationTitle("Nastavení")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
        // Sheets
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
        // Logout alert
        .alert("Opravdu se chcete odhlásit?", isPresented: $showLogoutConfirm) {
            Button("Zrušit", role: .cancel) { }
            Button("Odhlásit", role: .destructive) {
                authState.logOut()
            }
        } message: {
            Text("Budete odhlášeni z vašeho účtu.")
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                smallAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                    if let username = authState.currentUser?.username, !username.isEmpty {
                        Text("@\(username)")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else if let email = authState.currentUser?.email, !email.isEmpty {
                        Text(email)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
                Spacer()
                Button("Upravit") { isShowingEdit = true }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button {
                    isShowingEdit = true
                } label: {
                    Label("Upravit profil", systemImage: "pencil")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    isShowingEdit = true
                } label: {
                    Label("Upravit", systemImage: "pencil")
                }
            }
        } header: {
            Text("Účet")
        }
    }

    private var contactSection: some View {
        Section("Kontakt") {
            HStack {
                Label("E‑mail", systemImage: "envelope")
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(authState.currentUser?.email?.isEmpty == false ? (authState.currentUser?.email ?? "") : "Neznámý")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Label("Osobní číslo", systemImage: "person.text.rectangle")
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(personalNumberDisplay)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var settingsLogoutSection: some View {
        Section {
            Button {
                isShowingSettings = true
            } label: {
                Label("Nastavení", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }

            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                Label("Odhlásit se", systemImage: "rectangle.portrait.and.arrow.right")
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: - Helpers

    private var avatarInToolbar: some View {
        Group {
            if let url = authState.currentUser?.profileImageURL {
                AuthenticatedProfileImageView(
                    url: url,
                    token: authState.authToken
                )
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .contentShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .accessibilityHidden(true)
    }

    private var smallAvatar: some View {
        Group {
            if let url = authState.currentUser?.profileImageURL {
                AuthenticatedProfileImageView(
                    url: url,
                    token: authState.authToken
                )
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .contentShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .accessibilityHidden(true)
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
    ProfileView()
        .environmentObject(AuthState())
}

