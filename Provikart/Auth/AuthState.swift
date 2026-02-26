//
//  AuthState.swift
//  Provikart
//
//  Globální stav přihlášení – perzistovaný mezi spuštěními.
//

import Foundation

final class AuthState: ObservableObject {
    private let key = "Provikart.isLoggedIn"

    @Published private(set) var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: key)
        }
    }

    init() {
        self.isLoggedIn = UserDefaults.standard.bool(forKey: key)
    }

    func setLoggedIn(_ value: Bool) {
        isLoggedIn = value
    }

    func logOut() {
        setLoggedIn(false)
    }
}
