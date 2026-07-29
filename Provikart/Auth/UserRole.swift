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

    /// Role, které mobilní aplikace umí obsloužit.
    var isSupportedInApp: Bool {
        switch self {
        case .manager, .user:
            return true
        case .unknown:
            return false
        }
    }
}
