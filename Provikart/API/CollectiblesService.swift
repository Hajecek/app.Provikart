//
//  CollectiblesService.swift
//  Provikart
//
//  Sběratelská kolekce + denní bedna.
//  GET/POST collectibles.php, POST collectibles_chest.php
//

import Foundation
import ImageIO
import UIKit

// MARK: - Models

struct CollectiblesCurrency: Codable, Equatable {
    let key: String
    let name: String
    let nameOf: String

    enum CodingKeys: String, CodingKey {
        case key, name
        case nameOf = "name_of"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? "star_dust"
        name = (try? c.decode(String.self, forKey: .name)) ?? "Hvězdný prach"
        nameOf = (try? c.decode(String.self, forKey: .nameOf)) ?? "hvězdného prachu"
    }

    init(key: String = "star_dust", name: String = "Hvězdný prach", nameOf: String = "hvězdného prachu") {
        self.key = key
        self.name = name
        self.nameOf = nameOf
    }
}

struct CollectibleItem: Decodable, Equatable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let rarity: String
    let owned: Bool
    let qty: Int
    /// Kolik prachu ještě chybí k odemčení (craft).
    let need: Int?
    /// Prach aktuálně přiřazený na předmět.
    let allocatedPowder: Int
    let imageURL: String?
    let imageName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, rarity, owned, qty, need
        case image_url, imageUrl, image, image_name, imageName, thumbnail, thumb_url
        case desc, subtitle
        case powder, allocated, dust, progress, filled, powder_on_item, powderOnItem
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeInt(c, keys: [.id]) ?? 0
        name = Self.decodeString(c, keys: [.name]) ?? "Artefakt"
        description = Self.decodeString(c, keys: [.description, .desc, .subtitle])
        rarity = (Self.decodeString(c, keys: [.rarity]) ?? "common").lowercased()
        owned = Self.decodeBool(c, keys: [.owned]) ?? false
        qty = Self.decodeInt(c, keys: [.qty]) ?? 0
        need = Self.decodeInt(c, keys: [.need])
        allocatedPowder = Self.decodeInt(c, keys: [.powder, .allocated, .dust, .progress, .filled, .powder_on_item, .powderOnItem]) ?? 0
        imageURL = Self.decodeString(c, keys: [.image_url, .imageUrl, .image, .thumbnail, .thumb_url])
        imageName = Self.decodeString(c, keys: [.image_name, .imageName])
    }

    /// Zbývá k craftu (0 = lze craftnout).
    var remainingToCraft: Int {
        max(0, need ?? 0)
    }

    var canCraft: Bool {
        !owned && remainingToCraft == 0
    }

    var resolvedImageURL: URL? {
        guard let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            if let imageName, !imageName.isEmpty {
                let encoded = imageName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? imageName
                return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
            }
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://provikart.cz/\(trimmed)")
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Int? {
        for key in keys {
            if let v = try? c.decode(Int.self, forKey: key) { return v }
            if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
            if let d = try? c.decode(Double.self, forKey: key) { return Int(d) }
        }
        return nil
    }

    private static func decodeString(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for key in keys {
            if let v = try? c.decode(String.self, forKey: key) {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    private static func decodeBool(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Bool? {
        for key in keys {
            if let v = try? c.decode(Bool.self, forKey: key) { return v }
            if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
            if let s = try? c.decode(String.self, forKey: key) {
                let t = s.lowercased()
                if ["1", "true", "yes"].contains(t) { return true }
                if ["0", "false", "no"].contains(t) { return false }
            }
        }
        return nil
    }
}

struct CollectiblesChestOpenResult: Equatable {
    let duplicate: Bool
    let powderGained: Int
    let balance: Int
    let qty: Int
    let currency: CollectiblesCurrency
    let item: CollectibleItem
    let message: String
}

struct CollectiblesInventory: Equatable {
    let wallet: Int
    let currency: CollectiblesCurrency
    let ownedCount: Int
    let total: Int
    let items: [CollectibleItem]
}

// MARK: - Errors

enum CollectiblesError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná adresa API"
        case .notAuthenticated: return "Nejste přihlášeni"
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - API envelopes

private struct CollectiblesAPIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let error: String?
    let data: T?
}

private struct CollectiblesChestDataDTO: Decodable {
    let duplicate: Bool?
    let powder_gained: Int?
    let powderGained: Int?
    let balance: Int?
    let qty: Int?
    let currency: CollectiblesCurrency?
    let item: CollectibleItem?
    let message: String?
}

private struct CollectiblesInventoryDataDTO: Decodable {
    let wallet: Int?
    let currency: CollectiblesCurrency?
    let owned_count: Int?
    let total: Int?
    let items: [CollectibleItem]?
}

// MARK: - Service

final class CollectiblesService {
    private let baseURL = "https://provikart.cz/api"

    /// POST /api/collectibles_chest.php – otevře denní sběratelskou bednu.
    func openChest(token: String?) async throws -> CollectiblesChestOpenResult {
        guard let token, !token.isEmpty else { throw CollectiblesError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/collectibles_chest.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { throw CollectiblesError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token])

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CollectiblesError.serverError("Neplatná odpověď serveru")
        }

        let envelope = try? JSONDecoder().decode(CollectiblesAPIEnvelope<CollectiblesChestDataDTO>.self, from: data)
        let serverError = envelope?.error ?? Self.extractError(from: data)

        switch http.statusCode {
        case 200:
            guard envelope?.success != false, let dto = envelope?.data, let item = dto.item else {
                throw CollectiblesError.serverError(serverError ?? "Bednu se nepodařilo otevřít.")
            }
            let currency = dto.currency ?? CollectiblesCurrency()
            let duplicate = dto.duplicate ?? false
            let powder = dto.powder_gained ?? dto.powderGained ?? 0
            let qty = dto.qty ?? item.qty
            let balance = dto.balance ?? 0
            let message = dto.message ?? (
                duplicate
                    ? "Duplicita! +\(powder) \(currency.nameOf), celkem ×\(qty)"
                    : "Nový předmět ve sbírce: \(item.name)"
            )
            return CollectiblesChestOpenResult(
                duplicate: duplicate,
                powderGained: powder,
                balance: balance,
                qty: qty,
                currency: currency,
                item: item,
                message: message
            )
        case 401:
            throw CollectiblesError.notAuthenticated
        default:
            throw CollectiblesError.serverError(serverError ?? "Chyba serveru (\(http.statusCode))")
        }
    }

    /// GET /api/collectibles.php – inventář + zásoba prachu.
    func fetchInventory(token: String?) async throws -> CollectiblesInventory {
        guard let token, !token.isEmpty else { throw CollectiblesError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/collectibles.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { throw CollectiblesError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CollectiblesError.serverError("Neplatná odpověď serveru")
        }

        let envelope = try? JSONDecoder().decode(CollectiblesAPIEnvelope<CollectiblesInventoryDataDTO>.self, from: data)
        let serverError = envelope?.error ?? Self.extractError(from: data)

        switch http.statusCode {
        case 200:
            guard envelope?.success != false, let dto = envelope?.data else {
                throw CollectiblesError.serverError(serverError ?? "Inventář se nepodařilo načíst.")
            }
            return CollectiblesInventory(
                wallet: dto.wallet ?? 0,
                currency: dto.currency ?? CollectiblesCurrency(),
                ownedCount: dto.owned_count ?? 0,
                total: dto.total ?? (dto.items?.count ?? 0),
                items: dto.items ?? []
            )
        case 401:
            throw CollectiblesError.notAuthenticated
        default:
            throw CollectiblesError.serverError(serverError ?? "Chyba serveru (\(http.statusCode))")
        }
    }

    /// POST allocate|recall|craft
    func performAction(
        token: String?,
        action: String,
        collectibleId: Int,
        amount: Int = 0
    ) async throws -> CollectiblesInventory {
        guard let token, !token.isEmpty else { throw CollectiblesError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/collectibles.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { throw CollectiblesError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")

        let body: [String: Any] = [
            "token": token,
            "action": action,
            "collectible_id": collectibleId,
            "amount": amount
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CollectiblesError.serverError("Neplatná odpověď serveru")
        }

        let envelope = try? JSONDecoder().decode(CollectiblesAPIEnvelope<CollectiblesInventoryDataDTO>.self, from: data)
        // POST returns nested structure; fall back to refetch inventory
        if http.statusCode == 401 {
            throw CollectiblesError.notAuthenticated
        }
        if http.statusCode != 200 || envelope?.success == false {
            let err = envelope?.error ?? Self.extractError(from: data) ?? "Akce selhala."
            throw CollectiblesError.serverError(err)
        }

        return try await fetchInventory(token: token)
    }

    private static func extractError(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let error = obj["error"] as? String, !error.isEmpty { return error }
        if let message = obj["message"] as? String, !message.isEmpty { return message }
        return nil
    }
}

// MARK: - Shared image cache (sbírka + lucky box)

final class CollectibleImageCache: @unchecked Sendable {
    static let shared = CollectibleImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let inFlightLock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 40 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "collectible_images"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    private func key(for url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize.rounded()))"
    }

    func imageIfCached(for url: URL, maxPixelSize: CGFloat = 1200) -> UIImage? {
        cache.object(forKey: key(for: url, maxPixelSize: maxPixelSize) as NSString)
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let cacheKey = key(for: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let existing: Task<UIImage?, Never>? = {
            inFlightLock.lock()
            defer { inFlightLock.unlock() }
            return inFlight[cacheKey]
        }()
        if let existing {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            defer {
                inFlightLock.lock()
                inFlight[cacheKey] = nil
                inFlightLock.unlock()
            }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return nil
                }
                guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                cache.setObject(image, forKey: cacheKey as NSString, cost: data.count)
                return image
            } catch {
                return nil
            }
        }

        inFlightLock.lock()
        inFlight[cacheKey] = task
        inFlightLock.unlock()

        return await task.value
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
