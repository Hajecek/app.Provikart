//
//  SettingsView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI
import LocalAuthentication

private enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Systém"
        case .light: return "Světlý"
        case .dark: return "Tmavý"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var authState: AuthState

    // Perzistence nastavení
    @AppStorage("settings.notifications.general") private var notificationsGeneral = true
    @AppStorage("settings.notifications.marketing") private var notificationsMarketing = false
    @AppStorage("settings.notifications.orders") private var notificationsOrders = true

    @AppStorage("settings.appearance.mode") private var appearanceRaw: String = AppearanceMode.system.rawValue

    @AppStorage("settings.security.biometricEnabled") private var biometricEnabled = true

    @AppStorage("settings.data.useCellular") private var useCellularData = true

    // Lokální stav
    @State private var showClearCacheConfirm = false
    @State private var showOpenURLAlert = false
    @State private var pendingURL: URL?
    @State private var showBiometricUnavailableAlert = false

    private var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    // Převedení volby na ColorScheme
    private var preferredScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Verze \(version) (\(build))"
    }

    private var biometricTypeName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Biometrie"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometrie"
        }
    }

    var body: some View {
        Form {
            accountSection
            notificationsSection
            appearanceSection
            securitySection
            dataSection
            aboutSection
            signOutSection
        }
        .navigationTitle("Nastavení")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Biometrie není k dispozici", isPresented: $showBiometricUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Na tomto zařízení není biometrické ověření dostupné nebo je vypnuto v systému.")
        }
        .alert("Vymazat cache?", isPresented: $showClearCacheConfirm) {
            Button("Zrušit", role: .cancel) { }
            Button("Vymazat", role: .destructive) {
                clearAppCache()
            }
        } message: {
            Text("Vymažou se dočasná data (obrázky, odpovědi API).")
        }
        .alert("Otevřít odkaz", isPresented: $showOpenURLAlert) {
            Button("Zrušit", role: .cancel) { pendingURL = nil }
            Button("Otevřít") {
                if let url = pendingURL {
                    UIApplication.shared.open(url)
                }
                pendingURL = nil
            }
        } message: {
            Text("Otevřít tento odkaz v prohlížeči?")
        }
        .onChange(of: biometricEnabled) { _, newValue in
            if newValue, !deviceSupportsBiometrics() {
                biometricEnabled = false
                showBiometricUnavailableAlert = true
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            HStack {
                Label("Uživatel", systemImage: "person.circle")
                Spacer()
                Text(displayName)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("E‑mail", systemImage: "envelope")
                Spacer()
                Text(authState.currentUser?.email ?? "—")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Účet")
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsGeneral) {
                Label("Obecná oznámení", systemImage: "bell")
            }
            Toggle(isOn: $notificationsOrders) {
                Label("Stav objednávek", systemImage: "shippingbox")
            }
            Toggle(isOn: $notificationsMarketing) {
                Label("Marketingová oznámení", systemImage: "megaphone")
            }
            .tint(.orange)
        } header: {
            Text("Oznámení")
        } footer: {
            Text("Oznámení můžete spravovat i v Nastavení systému.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(
                selection: Binding<AppearanceMode>(
                    get: { appearance },
                    set: { newValue in
                        appearanceRaw = newValue.rawValue
                    }
                ),
                content: {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode as AppearanceMode)
                    }
                },
                label: {
                    Label("Režim", systemImage: "circle.lefthalf.filled")
                }
            )
        } header: {
            Text("Vzhled")
        } footer: {
            Text("Systém použije výchozí režim podle nastavení zařízení.")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: $biometricEnabled) {
                Label("Odemknout pomocí \(biometricTypeName)", systemImage: "lock.circle")
            }
            .onChange(of: biometricEnabled) { _, enabled in
                if enabled && !deviceSupportsBiometrics() {
                    biometricEnabled = false
                    showBiometricUnavailableAlert = true
                }
            }

            NavigationLink {
                Text("Změna hesla (placeholder)")
                    .navigationTitle("Změna hesla")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Změnit heslo", systemImage: "key")
            }
        } header: {
            Text("Zabezpečení")
        } footer: {
            Text("Pro vyšší zabezpečení používejte silné heslo a biometrické ověření.")
        }
    }

    private var dataSection: some View {
        Section {
            Toggle(isOn: $useCellularData) {
                Label("Používat mobilní data", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button(role: .destructive) {
                showClearCacheConfirm = true
            } label: {
                Label("Vymazat cache", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Vymazání cache může dočasně prodloužit načítání obsahu.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Verze", systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            Button {
                openExternal(URL(string: "https://provikart.cz/terms"))
            } label: {
                Label("Podmínky použití", systemImage: "doc.text")
            }

            Button {
                openExternal(URL(string: "https://provikart.cz/privacy"))
            } label: {
                Label("Zásady ochrany soukromí", systemImage: "hand.raised")
            }

            Button {
                openExternal(URL(string: "mailto:support@provikart.cz"))
            } label: {
                Label("Kontakt na podporu", systemImage: "envelope.open")
            }
        } header: {
            Text("O aplikaci")
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                authState.logOut()
            } label: {
                HStack {
                    Spacer()
                    Text("Odhlásit")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func deviceSupportsBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private func clearAppCache() {
        // Placeholder: sem může přijít mazání URLCache, souborů v tmp apod.
        URLCache.shared.removeAllCachedResponses()
        // případně: try? FileManager.default.removeItem(atPath: NSTemporaryDirectory())
        print("[Settings] Cache cleared")
    }

    private func openExternal(_ url: URL?) {
        guard let url else { return }
        pendingURL = url
        showOpenURLAlert = true
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(SettingsView_PreviewsScheme())
    .environmentObject(AuthState())
}

// Helper pro Preview: čte uložení z @AppStorage a vrací ColorScheme?
private func SettingsView_PreviewsScheme() -> ColorScheme? {
    let raw = UserDefaults.standard.string(forKey: "settings.appearance.mode") ?? AppearanceMode.system.rawValue
    let mode = AppearanceMode(rawValue: raw) ?? .system
    switch mode {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
}
