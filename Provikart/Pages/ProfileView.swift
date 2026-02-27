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
    @State private var isShowingSupport = false
    @State private var isShowingOrders = false
    @State private var isShowingSaved = false
    @State private var isShowingPayments = false
    @State private var isShowingAddresses = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            // iOS-like Profile: Form with sections
            Form {
                accountSection
                contactSection
                quickActionsSection
                listsSection
                paymentsAddressesSection
                supportLogoutSection
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Skupina vlevo: avatar + úpravy profilu
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isShowingEdit = true
                    } label: {
                        avatarInToolbar
                    }
                    .accessibilityLabel("Profil")
                }
                // Skupina vpravo: nastavení a sdílení
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shareProfile()
                    } label: {
                        Label("Sdílet", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Sdílet profil")
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Nastavení", systemImage: "gearshape")
                    }
                    .accessibilityLabel("Nastavení")
                }
                // Spodní toolbar (Liquid Glass) – časté akce s grupováním
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Domů", systemImage: "house.fill")
                    }
                    .accessibilityLabel("Zpět na Domů")
                    Button {
                        shareProfile()
                    } label: {
                        Label("Sdílet", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Nastavení", systemImage: "gearshape")
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            // Hidden NavigationLink to push SettingsView (iOS-like)
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

    private var quickActionsSection: some View {
        Section {
            HStack {
                statItem(value: "12", label: "Objednávky")
                Divider()
                statItem(value: "5", label: "Uložené")
                Divider()
                statItem(value: "3", label: "Adresy")
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Rychlé přehledy")
        }
    }

    private var listsSection: some View {
        Section {
            NavigationLink {
                // Placeholder obsahy – můžete nahradit skutečnými obrazovkami
                Text("Moje objednávky")
                    .navigationTitle("Objednávky")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                rowLabel(icon: "bag", title: "Moje objednávky", subtitle: "Historie a stav")
            }

            NavigationLink {
                Text("Uložené položky")
                    .navigationTitle("Uložené")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                rowLabel(icon: "bookmark", title: "Uložené", subtitle: "Oblíbené položky")
            }
        } header: {
            Text("Seznamy")
        }
    }

    private var paymentsAddressesSection: some View {
        Section {
            NavigationLink {
                Text("Platební metody")
                    .navigationTitle("Platby")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                rowLabel(icon: "creditcard", title: "Platební metody", subtitle: "Karty a Apple Pay")
            }

            NavigationLink {
                Text("Adresy")
                    .navigationTitle("Adresy")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                rowLabel(icon: "house", title: "Adresy", subtitle: "Doručovací a fakturační")
            }
        } header: {
            Text("Platby a doručení")
        }
    }

    private var supportLogoutSection: some View {
        Section {
            NavigationLink {
                Text("Podpora")
                    .navigationTitle("Podpora")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                rowLabel(icon: "questionmark.circle", title: "Podpora", subtitle: "FAQ a kontakt")
            }

            Button(role: .none) {
                shareProfile()
            } label: {
                rowLabel(icon: "square.and.arrow.up", title: "Sdílet profil", subtitle: nil)
            }
            .contextMenu {
                Button {
                    shareProfile()
                } label: {
                    Label("Sdílet profil", systemImage: "square.and.arrow.up")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    shareProfile()
                } label: {
                    Label("Sdílet", systemImage: "square.and.arrow.up")
                }
            }

            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                rowLabel(icon: "rectangle.portrait.and.arrow.right", title: "Odhlásit se", subtitle: nil, destructive: true)
            }
            .contextMenu {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("Odhlásit se", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("Odhlásit", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } header: {
            Text("Ostatní")
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

    private func rowLabel(icon: String, title: String, subtitle: String?, destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(destructive ? .red : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(destructive ? .red : .primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func shareProfile() {
        // Zde případně vytvořte skutečné sdílení profilu
        print("[Profile] Share tapped]")
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

    private var userBio: String? {
        // Pokud API doplní bio, napojte sem. Prozatím placeholder:
        return nil
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

