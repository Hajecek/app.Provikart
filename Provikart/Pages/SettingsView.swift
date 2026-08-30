//
//  SettingsView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI
import UserNotifications

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
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("settings.appearance.mode") private var appearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage("settings.liveActivity.enabled") private var liveActivityEnabled = true
    @ObservedObject private var prefs = NotificationPreferencesStore.shared

    @State private var showClearCacheConfirm = false
    @State private var showOpenURLAlert = false
    @State private var pendingURL: URL?
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showDeleteError = false
    @State private var systemAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var syncTask: Task<Void, Never>?

    private var isManagerRole: Bool {
        authState.currentRole == .manager
    }

    private var notificationRole: UserRole {
        isManagerRole ? .manager : .user
    }

    private var notificationChannels: [NotificationChannel] {
        NotificationChannel.channels(for: notificationRole)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var liveActivityToggleTitle: String {
        isManagerRole
            ? "Tým na Lock Screenu a v Dynamic Island"
            : "Provize na Lock Screenu a v Dynamic Island"
    }

    private var liveActivityFooter: String {
        isManagerRole
            ? "Když je zapnuto, aplikace zobrazí otevřené problémy týmu a docházku na Lock Screenu a v Dynamic Island."
            : "Když je zapnuto, aplikace zobrazí aktuální provizi a postup k cíli na Lock Screenu a v Dynamic Island."
    }

    private var notificationsFooter: String {
        isManagerRole
            ? "Vyberte, které události z týmu vám mají chodit jako push. Oznámení můžete spravovat i v Nastavení systému."
            : "Vyberte, které události vám mají chodit jako push. Oznámení můžete spravovat i v Nastavení systému."
    }

    var body: some View {
        List {
            Section {
                Picker("Režim vzhledu", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Vzhled")
            }

            notificationsSection

            Section {
                Toggle(isOn: $liveActivityEnabled) {
                    Label(liveActivityToggleTitle, systemImage: "livephoto")
                }
                .onChange(of: liveActivityEnabled) { _, enabled in
                    if !enabled {
                        if isManagerRole {
                            ManagerTeamLiveActivityManager.endAll()
                        } else {
                            CommissionLiveActivityManager.endAll()
                        }
                    }
                }
            } header: {
                Text("Live Activity")
            } footer: {
                Text(liveActivityFooter)
            }

            Section {
                LabeledContent("Verze", value: appVersion)

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

                Button("Vymazat cache", role: .destructive) {
                    showClearCacheConfirm = true
                }
            } header: {
                Text("O aplikaci")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    HStack {
                        Text("Smazat účet")
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
        .listStyle(.insetGrouped)
        .navigationTitle("Nastavení")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshNotificationStatus() }
        }
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

    @ViewBuilder
    private var notificationsSection: some View {
        if systemAuthStatus == .denied {
            Section {
                Button("Otevřít Nastavení") {
                    openSystemSettings()
                }
            } header: {
                Text("Oznámení")
            } footer: {
                Text("Oznámení jsou vypnutá v iOS. Zapněte je v Nastavení systému, aby vám mohla chodit.")
            }
        } else if systemAuthStatus == .notDetermined {
            Section {
                Button("Povolit oznámení") {
                    requestNotificationPermission()
                }
            } header: {
                Text("Oznámení")
            } footer: {
                Text("Povolte oznámení, abyste si mohli vybrat, které typy vám mají chodit.")
            }
        } else {
            Section {
                Toggle(isOn: Binding(
                    get: { prefs.masterEnabled },
                    set: { newValue in
                        withAnimation {
                            prefs.masterEnabled = newValue
                        }
                        if newValue, systemAuthStatus == .authorized || systemAuthStatus == .provisional {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                        schedulePreferenceSync()
                    }
                )) {
                    Label("Push oznámení", systemImage: "bell")
                }

                if prefs.masterEnabled {
                    ForEach(notificationChannels) { channel in
                        Toggle(isOn: Binding(
                            get: { prefs.isEnabled(channel) },
                            set: { newValue in
                                prefs.setEnabled(channel, newValue)
                                schedulePreferenceSync()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title)
                                Text(channel.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Oznámení")
            } footer: {
                Text(notificationsFooter)
            }
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                systemAuthStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                refreshNotificationStatus()
                if granted {
                    prefs.masterEnabled = true
                    UIApplication.shared.registerForRemoteNotifications()
                    schedulePreferenceSync()
                }
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func schedulePreferenceSync() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            appDelegate.syncNotificationPreferences(role: notificationRole)
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
        CollectibleImageCache.shared.clearAll()
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
    .environmentObject(AppDelegate())
}
