//
//  AuthSession.swift
//  Provikart
//
//  HTTP 401/403 se jen zaloguje. Přihlášení se neruší – odhlásit jde jen ručně.
//

import Foundation

extension Notification.Name {
    static let provikartAuthSessionInvalidated = Notification.Name("Provikart.authSessionInvalidated")
}

enum AuthSession {
    /// Automatické odhlášení je vypnuté. Token v aplikaci platí, dokud se uživatel neodhlásí sám.
    static func handle(http: HTTPURLResponse, data: Data?) {
        guard http.statusCode == 401 || http.statusCode == 403 else { return }
        Log.auth.notice("HTTP \(http.statusCode, privacy: .public) \(http.url?.path ?? "", privacy: .public) – relace se ponechává")
    }
}

extension URLSession {
    /// Stejné jako `data(for:)`, dřív vyhodnocovalo neplatnou session.
    func authAwareData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result = try await data(for: request)
        if let http = result.1 as? HTTPURLResponse {
            AuthSession.handle(http: http, data: result.0)
        }
        return result
    }
}
