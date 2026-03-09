//
//  SettingsView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

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
    @AppStorage("settings.appearance.mode") private var appearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage("settings.notifications.general") private var notificationsGeneral = true
    @AppStorage("settings.notifications.orders") private var notificationsOrders = true
    @AppStorage("settings.notifications.marketing") private var notificationsMarketing = false
    @State private var showClearCacheConfirm = false
    @State private var showOpenURLAlert = false
    @State private var pendingURL: URL?
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showDeleteError = false

    private var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Verze \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Picker(
                    selection: Binding(
                        get: { appearance },
                        set: { appearanceRaw = $0.rawValue }
                    ),
                    content: {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode as AppearanceMode)
                        }
                    },
                    label: {
                        Label("Režim vzhledu", systemImage: "circle.lefthalf.filled")
                    }
                )
            } header: {
                Text("Vzhled")
            }

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

                Button(role: .destructive) {
                    showClearCacheConfirm = true
                } label: {
                    Label("Vymazat cache", systemImage: "trash")
                }
            } header: {
                Text("O aplikaci")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    HStack {
                        Label("Smazat účet", systemImage: "person.crop.circle.badge.minus")
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeletingAccount)
            } header: {
                Text("Účet")
            } footer: {
                Text("Trvale smaže váš účet a všechna data z našich serverů.")
            }
        }
        .navigationTitle("Nastavení")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Vymazat cache?", isPresented: $showClearCacheConfirm) {
            Button("Zrušit", role: .cancel) { }
            Button("Vymazat", role: .destructive) { clearAppCache() }
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
        .alert("Opravdu smazat účet?", isPresented: $showDeleteAccountConfirm) {
            Button("Zrušit", role: .cancel) { }
            Button("Smazat účet", role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text("""
            Tato akce je nevratná. Budou trvale smazány:

            • Všechny vaše objednávky a jejich položky
            • Všechny nahlášené problémy
            • Přihlašovací tokeny a push notifikace
            • Váš uživatelský účet

            Po smazání se nebudete moci přihlásit a data nelze obnovit.
            """)
        }
        .alert("Chyba při mazání účtu", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteAccountError ?? "Neznámá chyba. Zkuste to prosím později.")
        }
    }

    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            let response = try await DeleteAccountService().deleteAccount(token: authState.authToken)
            if response.success {
                await MainActor.run {
                    authState.logOut()
                }
            } else {
                deleteAccountError = response.error ?? "Nepodařilo se smazat účet."
                showDeleteError = true
            }
        } catch {
            deleteAccountError = error.localizedDescription
            showDeleteError = true
        }
    }

    private func clearAppCache() {
        URLCache.shared.removeAllCachedResponses()
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
    .environmentObject(AuthState())
}
