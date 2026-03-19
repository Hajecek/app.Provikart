//
//  UserRole.swift
//  Provikart
//
//  Typově bezpečná role uživatele pro role-based UI.
//

import Foundation

enum UserRole: String {
    case manager
    case user
    case unknown

    init(apiValue: String?) {
        switch apiValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manager":
            self = .manager
        case "user", "employee":
            self = .user
        default:
            self = .unknown
        }
    }
}
