//
//  AikaAPI.swift
//  Provikart
//
//  Serverové API asistentky AIKA (složka aika/ na webu):
//   - POST {base}/aika/api/session.php → krátkodobý token pro ElevenLabs + dynamické proměnné
//   - GET  {base}/aika/api/tools.php   → seznam nástrojů (client tools agenta)
//   - POST {base}/aika/api/tool.php    → spuštění nástroje, `output` se vrací agentovi beze změny
//  Žádný klíč ElevenLabs/OpenAI v aplikaci není – vše drží server.
//

import Foundation

enum AikaConfig {
    /// Klíč v UserDefaults pro přepsání adresy serveru (např. `-AikaBaseURL http://localhost/provikart`
    /// jako argument při spuštění v simulátoru).
    static let baseURLKey = "AikaBaseURL"
    /// Jen pro DEBUG: přepsání tokenu (lokální server má vlastní databázi tokenů), `-AikaToken …`.
    static let tokenOverrideKey = "AikaToken"

    static let defaultBaseURL = "https://provikart.cz"

    static var baseURL: String {
        let custom = UserDefaults.standard.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = custom.isEmpty ? defaultBaseURL : custom
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    static func token(from appToken: String?) -> String? {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: tokenOverrideKey), !t.isEmpty { return t }
        #endif
        return appToken
    }
}

struct AikaSession: Sendable {
    let token: String
    let conversationId: String?
    let agentId: String?
    let dynamicVariables: [String: String]
}

struct AikaAPIError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

struct AikaAPI: Sendable {
    let authToken: String
    let baseURL: String

    init(authToken: String, baseURL: String = AikaConfig.baseURL) {
        self.authToken = authToken
        self.baseURL = baseURL
    }

    private func request(_ path: String, method: String, body: [String: Any]? = nil, timeout: TimeInterval = 20) throws -> URLRequest {
        // Token i v query a X-Auth-Token: hosting (Apache/CGI) hlavičku Authorization často zahodí,
        // stejně to dělají ostatní služby aplikace.
        guard var comp = URLComponents(string: baseURL + path) else {
            throw AikaAPIError(message: "Neplatná adresa serveru AIKA.", status: 0)
        }
        comp.queryItems = (comp.queryItems ?? []) + [URLQueryItem(name: "token", value: authToken)]
        guard let url = comp.url else {
            throw AikaAPIError(message: "Neplatná adresa serveru AIKA.", status: 0)
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue(authToken, forHTTPHeaderField: "X-Auth-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    /// Provede požadavek a vrátí JSON objekt; `success:false` nebo HTTP chyba → AikaAPIError s českou zprávou.
    private func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 200, let json, json["success"] as? Bool == true {
            return json
        }
        let serverMsg = json?["error"] as? String
        let fallback: String
        switch status {
        case 401: fallback = "Přihlášení vypršelo. Odhlas se a přihlas znovu."
        case 403: fallback = "Aika je dostupná jen pro manažery."
        case 429: fallback = "Aika je teď vytížená. Zkus to za chvíli."
        case 503: fallback = "Aika teď není na serveru zapnutá."
        default: fallback = "Aika teď neodpovídá (\(status))."
        }
        throw AikaAPIError(message: serverMsg?.isEmpty == false ? serverMsg! : fallback, status: status)
    }

    func startSession() async throws -> AikaSession {
        let json = try await send(request("/aika/api/session.php", method: "POST", body: ["transport": "webrtc"]))
        guard let token = json["token"] as? String, !token.isEmpty else {
            throw AikaAPIError(message: "Server nevrátil token hovoru.", status: 200)
        }
        var vars: [String: String] = [:]
        for (k, v) in (json["dynamic_variables"] as? [String: Any]) ?? [:] {
            if let s = v as? String { vars[k] = s }
            else if JSONSerialization.isValidJSONObject(v),
                    let d = try? JSONSerialization.data(withJSONObject: v) { vars[k] = String(decoding: d, as: UTF8.self) }
            else { vars[k] = "\(v)" }
        }
        return AikaSession(
            token: token,
            conversationId: json["conversation_id"] as? String,
            agentId: json["agent_id"] as? String,
            dynamicVariables: vars
        )
    }

    func toolNames() async throws -> [String] {
        let json = try await send(request("/aika/api/tools.php", method: "GET"))
        let tools = json["tools"] as? [[String: Any]] ?? []
        return tools.compactMap { $0["name"] as? String }
    }

    /// Spustí nástroj na serveru; vrací `output` beze změny (i chyby jsou JSON uvnitř output).
    func runTool(name: String, argumentsJSON: Data) async -> String {
        let args = ((try? JSONSerialization.jsonObject(with: argumentsJSON)) as? [String: Any]) ?? [:]
        do {
            let req = try request("/aika/api/tool.php", method: "POST", body: ["name": name, "arguments": args], timeout: 25)
            let (data, response) = try await URLSession.shared.data(for: req)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let output = json?["output"] as? String { return output }
            Log.aika.error("Nástroj \(name, privacy: .public): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0, privacy: .public) bez output")
        } catch {
            Log.aika.error("Nástroj \(name, privacy: .public) selhal: \(error.localizedDescription, privacy: .public)")
        }
        return #"{"error":"Nástroj teď nefunguje."}"#
    }
}
