//
//  SessionUnlockState.swift
//  Provikart
//
//  Sdílený stav: uživatel prošel biometrickým ověřením v této session.
//

import Foundation
import SwiftUI

@MainActor
final class SessionUnlockState: ObservableObject {
    /// `true` až po úspěšném ověření (Face ID / Touch ID).
    @Published var isUnlocked = false

    func lock() {
        isUnlocked = false
    }

    func unlock() {
        isUnlocked = true
    }
}

private struct SessionUnlockedKey: EnvironmentKey {
    /// Ve preview / bez injectu považujeme session za odemčenou.
    static let defaultValue = true
}

extension EnvironmentValues {
    var sessionUnlocked: Bool {
        get { self[SessionUnlockedKey.self] }
        set { self[SessionUnlockedKey.self] = newValue }
    }
}
