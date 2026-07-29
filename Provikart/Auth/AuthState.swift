//
//  AuthState.swift
//  Provikart
//
//  Globální stav přihlášení – perzistovaný mezi spuštěními.
//

import Foundation

final class AuthState: ObservableObject {
    private let key = "Provikart.isLoggedIn"
    private let userKey = "Provikart.currentUser"
    private let tokenKey = "Provikart.authToken"

    @Published private(set) var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: key)
            if !isLoggedIn {
                currentUser = nil
                authToken = nil
            }
        }
    }

    @Published private(set) var currentUser: UserInfo? {
        didSet {
            if let user = currentUser, let data = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(data, forKey: userKey)
                WidgetDataStore.saveUserRole(UserRole(apiValue: user.role))
            } else {
                UserDefaults.standard.removeObject(forKey: userKey)
                WidgetDataStore.clearUserRole()
            }
        }
    }

    /// Aktuální role uživatele mapovaná ze serverového stringu.
    var currentRole: UserRole {
        UserRole(apiValue: currentUser?.role)
    }

    /// Token pro autentizované požadavky (např. načtení profilového obrázku).
    @Published private(set) var authToken: String? {
        didSet {
            if let t = authToken {
                UserDefaults.standard.set(t, forKey: tokenKey)
                WidgetDataStore.saveAuthToken(t)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
                WidgetDataStore.clearAuthToken()
            }
            PhoneSessionManager.shared.sendToken(authToken)
        }
    }

    /// Zpráva na LoginView po vynuceném odhlášení kvůli vypršení relace (ne při ručním odhlášení).
    @Published private(set) var sessionExpiredNotice: String?

    static let sessionExpiredNoticeText =
        "Z bezpečnostních důvodů je potřeba se jednou za čas znovu přihlásit. Vaše relace vypršela."

    static let unsupportedRoleNoticeText =
        "Tomuto uživateli nebyla přidána oprávnění pro mobilní aplikaci."

    init() {
        self.isLoggedIn = UserDefaults.standard.bool(forKey: key)
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(UserInfo.self, from: data) {
            self.currentUser = user
        } else {
            self.currentUser = nil
        }
        self.authToken = UserDefaults.standard.string(forKey: tokenKey)
        if let user = currentUser {
            WidgetDataStore.saveUserRole(UserRole(apiValue: user.role))
        }
        // Rozbitá session (přihlášen bez tokenu) → rovnou login, ne FreeEntry.
        if isLoggedIn, authToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            isLoggedIn = false
            sessionExpiredNotice = Self.sessionExpiredNoticeText
        } else if isLoggedIn, !UserRole(apiValue: currentUser?.role).isSupportedInApp {
            // Uložená role, kterou appka neumí (např. national_manager).
            isLoggedIn = false
            sessionExpiredNotice = Self.unsupportedRoleNoticeText
        }
    }

    func setLoggedIn(_ value: Bool, user: UserInfo? = nil, token: String? = nil) {
        if value {
            if let user, !UserRole(apiValue: user.role).isSupportedInApp {
                sessionExpiredNotice = Self.unsupportedRoleNoticeText
                isLoggedIn = false
                currentUser = nil
                authToken = nil
                print("[AuthState] Odmítnuto přihlášení – nepodporovaná role: \(user.role ?? "nil")")
                return
            }
            sessionExpiredNotice = nil
        }
        isLoggedIn = value
        if let user = user {
            currentUser = user
            user.logToConsole()
        } else if !value {
            currentUser = nil
        }
        if let token = token {
            authToken = token
        } else if !value {
            authToken = nil
        }
    }

    func logOut() {
        sessionExpiredNotice = nil
        setLoggedIn(false)
    }

    /// Odhlásí jen při potvrzené neplatné session (401 / Forbidden), ne při výpadku sítě.
    func invalidateSessionDueToAuthFailure() {
        guard isLoggedIn || !(authToken?.isEmpty ?? true) else { return }
        print("[AuthState] Session neplatná – přesměrování na přihlášení")
        sessionExpiredNotice = Self.sessionExpiredNoticeText
        setLoggedIn(false)
    }

    func clearSessionExpiredNotice() {
        sessionExpiredNotice = nil
    }

    /// Aktualizuje uloženého uživatele (např. po načtení profilu/plánu ze serveru).
    /// Sloučí s existujícím uživatelem, aby se nepřepsala pole, která API nevrací (např. profile_image).
    func refreshCurrentUser(_ user: UserInfo) {
        if let existing = currentUser {
            currentUser = UserInfo(merging: user, existing: existing)
        } else {
            currentUser = user
        }
        currentUser?.logToConsole()

        if !UserRole(apiValue: currentUser?.role).isSupportedInApp {
            print("[AuthState] Role po obnovení profilu není podporovaná: \(currentUser?.role ?? "nil")")
            sessionExpiredNotice = Self.unsupportedRoleNoticeText
            setLoggedIn(false)
        }
    }
}
