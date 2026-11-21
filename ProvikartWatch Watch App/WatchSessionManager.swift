//
//  WatchSessionManager.swift
//  ProvikartWatch Watch App
//
//  WatchConnectivity na straně hodinek – přijímá auth token z iPhonu.
//

import Foundation
import Combine
import WatchConnectivity
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cz.provikart.watch", category: "Watch")

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
    
    @Published private(set) var userRole: String? {
        didSet { UserDefaults.standard.set(userRole, forKey: "Provikart.watchUserRole") }
    }

    private let appGroupIdentifier = "group.com.hajecek.provikartApp"

    private override init() {
        if let local = UserDefaults.standard.string(forKey: "Provikart.watchAuthToken"), !local.isEmpty {
            self.authToken = local
        } else if let shared = UserDefaults(suiteName: "group.com.hajecek.provikartApp")?.string(forKey: "widget_auth_token"), !shared.isEmpty {
            self.authToken = shared
        }
        self.userName = UserDefaults.standard.string(forKey: "Provikart.watchUserName")
        self.userRole = UserDefaults.standard.string(forKey: "Provikart.watchUserRole")
        if let urlStr = UserDefaults.standard.string(forKey: "Provikart.watchProfileImageURL"), !urlStr.isEmpty {
            self.profileImageURL = URL(string: urlStr)
        }
        super.init()
        log.debug("Init – token: \(self.authToken != nil ? "nalezen" : "žádný", privacy: .public)")
    }

    var isAuthenticated: Bool {
        guard let token = authToken else { return false }
        return !token.isEmpty
    }
    
    var isManager: Bool {
        (userRole ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "manager"
    }

    func activate() {
        guard WCSession.isSupported() else {
            log.debug("WatchConnectivity není podporováno")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        log.debug("WCSession aktivována")
    }

    /// Aktivně požádá iPhone o token (sendMessage s replyHandler).
    func requestTokenFromPhone() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            log.debug("WCSession není aktivní")
            tryAppGroupFallback()
            return
        }

        guard session.isReachable else {
            log.debug("iPhone není dosažitelný, zkouším App Group fallback")
            tryAppGroupFallback()
            return
        }

        session.sendMessage(["request": "token"], replyHandler: { response in
            if let token = response["authToken"] as? String {
                DispatchQueue.main.async {
                    self.authToken = token.isEmpty ? nil : token
                    self.updateUserInfo(from: response)
                    log.debug("Token přijat přes sendMessage: \(token.isEmpty ? "prázdný" : "OK", privacy: .public)")
                }
            }
        }, errorHandler: { error in
            log.error("sendMessage selhal: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self.tryAppGroupFallback() }
        })
    }

    /// Načte token z App Group UserDefaults (funguje na simulátoru, kde iPhone a Watch sdílejí kontejner).
    func tryAppGroupFallback() {
        guard !isAuthenticated else { return }
        if let token = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "widget_auth_token"), !token.isEmpty {
            self.authToken = token
            log.debug("Token načten z App Group fallback")
        } else {
            log.debug("App Group fallback: žádný token")
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
        if let role = dict["userRole"] as? String {
            let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
            self.userRole = trimmed.isEmpty ? nil : trimmed
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
            log.error("Aktivace selhala: \(error.localizedDescription, privacy: .public)")
            return
        }
        log.debug("Aktivace dokončena, stav: \(activationState.rawValue, privacy: .public), reachable: \(session.isReachable, privacy: .public)")

        // 1) applicationContext (přijde i bez běžícího iPhone)
        let context = session.receivedApplicationContext
        if let token = context["authToken"] as? String, !token.isEmpty {
            DispatchQueue.main.async {
                self.authToken = token
                self.updateUserInfo(from: context)
                log.debug("Token z applicationContext: přijat")
            }
            return
        }

        // 2) Pokud máme token z init (App Group / local), nemusíme dál
        if isAuthenticated {
            log.debug("Token již máme z init, přeskakuji další pokusy")
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
                log.debug("Token přijat přes applicationContext: \(token.isEmpty ? "odhlášení" : "přihlášení", privacy: .public)")
            }
        }
    }

    /// Příjem push zprávy od iPhonu (provize, počet služeb, token, apod.)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let type = message["type"] as? String {
            switch type {
            case "commissionUpdate":
                let commission = message["commission"] as? Double ?? 0
                let currency = message["currency"] as? String ?? "Kč"
                let monthLabel = message["monthLabel"] as? String
                let commissionGoal = message["commissionGoal"] as? Double
                var userInfo: [String: Any] = [
                    "commission": commission,
                    "currency": currency,
                    "monthLabel": monthLabel ?? ""
                ]
                if let goal = commissionGoal {
                    userInfo["commissionGoal"] = goal
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .watchCommissionDidUpdate,
                        object: nil,
                        userInfo: userInfo
                    )
                    log.debug("Provize přijata z iPhonu")
                }
            case "servicesCountUpdate":
                let count = message["count"] as? Int ?? 0
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .watchServicesCountDidUpdate,
                        object: nil,
                        userInfo: ["count": count]
                    )
                    log.debug("Počet služeb přijat z iPhonu: \(count, privacy: .public)")
                }
            default:
                break
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        log.debug("Reachability změna: \(session.isReachable, privacy: .public)")
        if session.isReachable, !isAuthenticated {
            requestTokenFromPhone()
        }
    }
}

extension Notification.Name {
    static let watchCommissionDidUpdate = Notification.Name("watchCommissionDidUpdate")
    static let watchServicesCountDidUpdate = Notification.Name("watchServicesCountDidUpdate")
}
