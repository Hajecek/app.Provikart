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
            Log.watch.debug("WatchConnectivity není na tomto zařízení podporováno")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Pošle auth token + profil na hodinky.
    func sendToken(_ token: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            Log.watch.debug("WCSession ještě není aktivní – token se pošle po aktivaci")
            return
        }

        let value = token ?? ""
        var context: [String: Any] = ["authToken": value]

        if let data = UserDefaults.standard.data(forKey: "Provikart.currentUser"),
           let user = try? JSONDecoder().decode(WatchUserPayload.self, from: data) {
            context["userName"] = user.displayName
            context["profileImageURL"] = user.profileImageURLString
            context["userRole"] = user.role ?? ""
        }

        do {
            try session.updateApplicationContext(context)
            Log.watch.info("Kontext pro hodinky odeslán (\(value.isEmpty ? "odhlášení" : "přihlášení", privacy: .public))")
        } catch {
            Log.watch.error("Kontext pro hodinky se nepodařilo odeslat: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pošle aktuální uložený token (např. po aktivaci session).
    func sendCurrentTokenIfNeeded() {
        let token = UserDefaults.standard.string(forKey: "Provikart.authToken")
        sendToken(token)
    }

    /// Pošle aktuální provizi na hodinky (volá se z HomeView po načtení).
    func sendCommissionUpdate(commission: Double, currency: String, monthLabel: String?, commissionGoal: Double? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        var data: [String: Any] = [
            "type": "commissionUpdate",
            "commission": commission,
            "currency": currency,
            "monthLabel": monthLabel ?? ""
        ]
        if let goal = commissionGoal {
            data["commissionGoal"] = goal
        }
        session.sendMessage(data, replyHandler: nil) { error in
            Log.watch.debug("Provizi se nepodařilo poslat na hodinky: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pošle počet služeb na hodinky (volá se z HomeView po načtení).
    func sendServicesCountUpdate(count: Int) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        let data: [String: Any] = [
            "type": "servicesCountUpdate",
            "count": count
        ]
        session.sendMessage(data, replyHandler: nil) { error in
            Log.watch.debug("Počet služeb se nepodařilo poslat na hodinky: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            Log.watch.error("Aktivace WCSession selhala: \(error.localizedDescription, privacy: .public)")
            return
        }
        Log.watch.debug("WCSession aktivní (stav \(activationState.rawValue, privacy: .public))")
        DispatchQueue.main.async {
            self.sendCurrentTokenIfNeeded()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        Log.watch.debug("WCSession neaktivní")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        Log.watch.debug("WCSession deaktivována – reaktivuji")
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
                reply["userRole"] = user.role ?? ""
            }

            Log.watch.info("Hodinky žádají token → \(token.isEmpty ? "prázdný" : "odesílám", privacy: .public)")
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
    let role: String?

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
