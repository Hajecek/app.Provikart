//
//  WatchSessionManager.swift
//  ProvikartWatch Watch App
//
//  WatchConnectivity na straně hodinek – přijímá auth token z iPhonu.
//

import Foundation
import Combine
import WatchConnectivity

final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published private(set) var authToken: String? {
        didSet {
            UserDefaults.standard.set(authToken, forKey: "Provikart.watchAuthToken")
            saveTokenToAppGroup(authToken)
        }
    }

    @Published private(set) var userName: String? {
        didSet { UserDefaults.standard.set(userName, forKey: "Provikart.watchUserName") }
    }

    @Published private(set) var profileImageURL: URL? {
        didSet { UserDefaults.standard.set(profileImageURL?.absoluteString, forKey: "Provikart.watchProfileImageURL") }
    }

    private let appGroupIdentifier = "group.com.hajecek.provikartApp"

    private override init() {
        if let local = UserDefaults.standard.string(forKey: "Provikart.watchAuthToken"), !local.isEmpty {
            self.authToken = local
        } else if let shared = UserDefaults(suiteName: "group.com.hajecek.provikartApp")?.string(forKey: "widget_auth_token"), !shared.isEmpty {
            self.authToken = shared
        }
        self.userName = UserDefaults.standard.string(forKey: "Provikart.watchUserName")
        if let urlStr = UserDefaults.standard.string(forKey: "Provikart.watchProfileImageURL"), !urlStr.isEmpty {
            self.profileImageURL = URL(string: urlStr)
        }
        super.init()
        print("[WC-Watch] Init – token: \(authToken != nil ? "nalezen" : "žádný")")
    }

    var isAuthenticated: Bool {
        guard let token = authToken else { return false }
        return !token.isEmpty
    }

    func activate() {
        guard WCSession.isSupported() else {
            print("[WC-Watch] WatchConnectivity není podporováno")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[WC-Watch] WCSession aktivována")
    }

    /// Aktivně požádá iPhone o token (sendMessage s replyHandler).
    func requestTokenFromPhone() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("[WC-Watch] WCSession není aktivní")
            tryAppGroupFallback()
            return
        }

        guard session.isReachable else {
            print("[WC-Watch] iPhone není dosažitelný, zkouším App Group fallback")
            tryAppGroupFallback()
            return
        }

        session.sendMessage(["request": "token"], replyHandler: { response in
            if let token = response["authToken"] as? String {
                DispatchQueue.main.async {
                    self.authToken = token.isEmpty ? nil : token
                    self.updateUserInfo(from: response)
                    print("[WC-Watch] Token přijat přes sendMessage: \(token.isEmpty ? "prázdný" : "OK")")
                }
            }
        }, errorHandler: { error in
            print("[WC-Watch] Chyba sendMessage: \(error.localizedDescription)")
            DispatchQueue.main.async { self.tryAppGroupFallback() }
        })
    }

    /// Načte token z App Group UserDefaults (funguje na simulátoru, kde iPhone a Watch sdílejí kontejner).
    func tryAppGroupFallback() {
        guard !isAuthenticated else { return }
        if let token = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "widget_auth_token"), !token.isEmpty {
            self.authToken = token
            print("[WC-Watch] Token načten z App Group fallback")
        } else {
            print("[WC-Watch] App Group fallback: žádný token")
        }
    }

    /// Aktualizuje profil z přijatého dictionary (applicationContext / sendMessage reply).
    func updateUserInfo(from dict: [String: Any]) {
        if let name = dict["userName"] as? String, !name.isEmpty {
            self.userName = name
        }
        if let urlStr = dict["profileImageURL"] as? String, !urlStr.isEmpty {
            self.profileImageURL = URL(string: urlStr)
        }
    }

    private func saveTokenToAppGroup(_ token: String?) {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        if let t = token, !t.isEmpty {
            suite.set(t, forKey: "widget_auth_token")
        } else {
            suite.removeObject(forKey: "widget_auth_token")
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WC-Watch] Aktivace selhala: \(error.localizedDescription)")
            return
        }
        print("[WC-Watch] Aktivace dokončena, stav: \(activationState.rawValue), reachable: \(session.isReachable)")

        // 1) applicationContext (přijde i bez běžícího iPhone)
        let context = session.receivedApplicationContext
        if let token = context["authToken"] as? String, !token.isEmpty {
            DispatchQueue.main.async {
                self.authToken = token
                self.updateUserInfo(from: context)
                print("[WC-Watch] Token z applicationContext: přijat")
            }
            return
        }

        // 2) Pokud máme token z init (App Group / local), nemusíme dál
        if isAuthenticated {
            print("[WC-Watch] Token již máme z init, přeskakuji další pokusy")
            return
        }

        // 3) sendMessage na iPhone
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestTokenFromPhone()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let token = applicationContext["authToken"] as? String {
            DispatchQueue.main.async {
                self.authToken = token.isEmpty ? nil : token
                self.updateUserInfo(from: applicationContext)
                print("[WC-Watch] Token přijat přes applicationContext: \(token.isEmpty ? "odhlášení" : "přihlášení")")
            }
        }
    }

    /// Příjem push zprávy od iPhonu (provize, token, apod.)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let type = message["type"] as? String, type == "commissionUpdate" {
            let commission = message["commission"] as? Double ?? 0
            let currency = message["currency"] as? String ?? "Kč"
            let monthLabel = message["monthLabel"] as? String
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .watchCommissionDidUpdate,
                    object: nil,
                    userInfo: [
                        "commission": commission,
                        "currency": currency,
                        "monthLabel": monthLabel ?? ""
                    ]
                )
                print("[WC-Watch] Provize přijata z iPhonu: \(commission) \(currency)")
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WC-Watch] Reachability změna: \(session.isReachable)")
        if session.isReachable, !isAuthenticated {
            requestTokenFromPhone()
        }
    }
}

extension Notification.Name {
    static let watchCommissionDidUpdate = Notification.Name("watchCommissionDidUpdate")
}
