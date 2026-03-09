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
            } else {
                UserDefaults.standard.removeObject(forKey: userKey)
            }
        }
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

    init() {
        self.isLoggedIn = UserDefaults.standard.bool(forKey: key)
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(UserInfo.self, from: data) {
            self.currentUser = user
        } else {
            self.currentUser = nil
        }
        self.authToken = UserDefaults.standard.string(forKey: tokenKey)
    }

    func setLoggedIn(_ value: Bool, user: UserInfo? = nil, token: String? = nil) {
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
        setLoggedIn(false)
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
    }
}
