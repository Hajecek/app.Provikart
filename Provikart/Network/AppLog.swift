//
//  AppLog.swift
//  Provikart
//
//  Jednotné logování přes `os.Logger` – v konzoli Xcode jde filtrovat podle
//  kategorie (`category:Auth`) i úrovně. Citlivé hodnoty (tokeny, e‑maily,
//  těla odpovědí) se logují jako `.private`, v release logu se tak nezobrazí.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "cz.provikart.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let push = Logger(subsystem: subsystem, category: "Push")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let realtime = Logger(subsystem: subsystem, category: "Realtime")
    static let orders = Logger(subsystem: subsystem, category: "Orders")
    static let ai = Logger(subsystem: subsystem, category: "AI")
    static let aika = Logger(subsystem: subsystem, category: "Aika")
    static let widget = Logger(subsystem: subsystem, category: "Widget")
    static let watch = Logger(subsystem: subsystem, category: "Watch")

    /// Zkrácený náhled těla odpovědi pro chybové logy.
    static func preview(_ data: Data, limit: Int = 300) -> String {
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
        return data.count > limit ? text + "…" : text
    }

    static func preview(_ text: String, limit: Int = 300) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

extension Error {
    /// Zrušený request (odchod z obrazovky, nový tick pollingu) – nelogovat jako chybu.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let url = self as? URLError, url.code == .cancelled { return true }
        return (self as NSError).domain == NSURLErrorDomain && (self as NSError).code == NSURLErrorCancelled
    }
}
