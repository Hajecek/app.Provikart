//
//  PhoneSessionManager.swift
//  Provikart
//
//  WatchConnectivity na straně iPhonu – posílá auth token na Apple Watch.
//

import Foundation
import WatchConnectivity

final class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            print("[WC-Phone] WatchConnectivity není podporováno na tomto zařízení")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[WC-Phone] WCSession aktivována")
    }

    /// Pošle auth token + profil na hodinky.
    func sendToken(_ token: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("[WC-Phone] WCSession ještě není aktivní, token se pošle po aktivaci")
            return
        }

        let value = token ?? ""
        var context: [String: Any] = ["authToken": value]

        if let data = UserDefaults.standard.data(forKey: "Provikart.currentUser"),
           let user = try? JSONDecoder().decode(WatchUserPayload.self, from: data) {
            context["userName"] = user.displayName
            context["profileImageURL"] = user.profileImageURLString
        }

        do {
            try session.updateApplicationContext(context)
            print("[WC-Phone] Context odeslán (\(value.isEmpty ? "odhlášení" : "přihlášení"))")
        } catch {
            print("[WC-Phone] Chyba applicationContext: \(error.localizedDescription)")
        }
    }

    /// Pošle aktuální uložený token (např. po aktivaci session).
    func sendCurrentTokenIfNeeded() {
        let token = UserDefaults.standard.string(forKey: "Provikart.authToken")
        sendToken(token)
    }

    /// Pošle aktuální provizi na hodinky (volá se z HomeView po načtení).
    func sendCommissionUpdate(commission: Double, currency: String, monthLabel: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        let data: [String: Any] = [
            "type": "commissionUpdate",
            "commission": commission,
            "currency": currency,
            "monthLabel": monthLabel ?? ""
        ]
        session.sendMessage(data, replyHandler: nil) { error in
            print("[WC-Phone] Chyba odesílání provize: \(error.localizedDescription)")
        }
    }
}

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WC-Phone] Aktivace selhala: \(error.localizedDescription)")
            return
        }
        print("[WC-Phone] Aktivace dokončena, stav: \(activationState.rawValue)")
        DispatchQueue.main.async {
            self.sendCurrentTokenIfNeeded()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WC-Phone] Session se stala neaktivní")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[WC-Phone] Session deaktivována, reaktivuji…")
        WCSession.default.activate()
    }

    /// Hodinky požádaly o token – odpovíme okamžitě.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "token" {
            let token = UserDefaults.standard.string(forKey: "Provikart.authToken") ?? ""
            var reply: [String: Any] = ["authToken": token]

            if let data = UserDefaults.standard.data(forKey: "Provikart.currentUser"),
               let user = try? JSONDecoder().decode(WatchUserPayload.self, from: data) {
                reply["userName"] = user.displayName
                reply["profileImageURL"] = user.profileImageURLString
            }

            print("[WC-Phone] Hodinky žádají token → \(token.isEmpty ? "prázdný" : "odesílám")")
            replyHandler(reply)
        }
    }
}

/// Minimální dekódování uživatele jen pro WatchConnectivity payload.
private struct WatchUserPayload: Codable {
    let firstname: String?
    let lastname: String?
    let name: String?
    let profile_image: String?

    var displayName: String {
        if let f = firstname, !f.isEmpty, let l = lastname, !l.isEmpty {
            return "\(f) \(l)"
        }
        return name ?? ""
    }

    var profileImageURLString: String {
        guard let img = profile_image, !img.isEmpty else { return "" }
        let encoded = img.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? img
        return "https://provikart.cz/auth/serve_image?file=\(encoded)"
    }
}
