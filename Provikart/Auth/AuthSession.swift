//
//  AuthSession.swift
//  Provikart
//
//  Detekce neplatné session (401 / plain Forbidden) → odhlášení na LoginView.
//  Neodhlašuje při běžných síťových chybách ani u JSON 403 s oprávněním.
//

import Foundation

extension Notification.Name {
    static let provikartAuthSessionInvalidated = Notification.Name("Provikart.authSessionInvalidated")
}

enum AuthSession {
    private static let lock = NSLock()
    private static var lastInvalidationAt: Date?

    /// Zpracuje HTTP odpověď. Při jasně neplatné session pošle notifikaci k odhlášení.
    static func handle(http: HTTPURLResponse, data: Data?) {
        guard shouldInvalidate(statusCode: http.statusCode, data: data) else { return }
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let last = lastInvalidationAt, now.timeIntervalSince(last) < 1.5 {
            return
        }
        lastInvalidationAt = now
        NotificationCenter.default.post(name: .provikartAuthSessionInvalidated, object: nil)
    }

    static func shouldInvalidate(statusCode: Int, data: Data?) -> Bool {
        if statusCode == 401 { return true }

        // Backend často vrací plain-text "Forbidden" místo 401 při neplatném tokenu.
        // Prázdné 403 / JSON s detailním oprávněním neodhlašujeme.
        guard statusCode == 403 else { return false }
        let raw = String(data: data ?? Data(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.caseInsensitiveCompare("Forbidden") == .orderedSame { return true }

        // JSON: {"error":"Forbidden"} bez success/message detailu oprávnění
        if let obj = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
           let err = (obj["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           err.caseInsensitiveCompare("Forbidden") == .orderedSame,
           obj["success"] == nil {
            return true
        }
        return false
    }
}

extension URLSession {
    /// Stejné jako `data(for:)`, navíc vyhodnotí neplatnou session.
    func authAwareData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result = try await data(for: request)
        if let http = result.1 as? HTTPURLResponse {
            AuthSession.handle(http: http, data: result.0)
        }
        return result
    }
}
