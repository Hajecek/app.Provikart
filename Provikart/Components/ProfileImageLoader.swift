//
//  ProfileImageLoader.swift
//  Provikart
//
//  Sdílená cache a načítání profilových fotek.
//  - paměťová cache (fotka se po odrolování a návratu nestahuje znovu),
//  - sloučení souběžných požadavků na stejnou URL,
//  - omezení počtu souběžných stažení (velké týmy nezahltí síť),
//  - zmenšení obrázku na velikost avataru (dekódování neblokuje scroll).
//

import ImageIO
import UIKit

actor ProfileImageLoader {
    static let shared = ProfileImageLoader()

    /// Synchronní přístup z view (NSCache je thread-safe).
    nonisolated(unsafe) let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// URL, které selhaly – během krátké doby je nezkoušíme znovu (žádné nekonečné načítání).
    private var failures: [String: Date] = [:]
    private let failureRetryInterval: TimeInterval = 120

    private let maxConcurrent = 6
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    nonisolated static func cacheKey(url: URL, pixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(pixelSize.rounded()))"
    }

    nonisolated func cachedImage(url: URL, pixelSize: CGFloat) -> UIImage? {
        memoryCache.object(forKey: Self.cacheKey(url: url, pixelSize: pixelSize) as NSString)
    }

    func image(urls: [URL], token: String?, pixelSize: CGFloat) async -> UIImage? {
        guard let primary = urls.first else { return nil }
        let key = Self.cacheKey(url: primary, pixelSize: pixelSize)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let failedAt = failures[key], Date().timeIntervalSince(failedAt) < failureRetryInterval {
            return nil
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [session] in
            await self.acquireSlot()
            defer { self.releaseSlot() }
            for url in urls {
                if let img = await Self.fetch(url: url, token: token, pixelSize: pixelSize, session: session) {
                    return img
                }
            }
            return nil
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            let cost = Int(result.size.width * result.size.height * result.scale * result.scale * 4)
            memoryCache.setObject(result, forKey: key as NSString, cost: cost)
            failures[key] = nil
        } else {
            failures[key] = Date()
        }
        return result
    }

    private func acquireSlot() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            running = max(0, running - 1)
        } else {
            // Slot předáme dalšímu čekajícímu, `running` zůstává stejné.
            waiters.removeFirst().resume()
        }
    }

    nonisolated private static func fetch(url: URL, token: String?, pixelSize: CGFloat, session: URLSession) async -> UIImage? {
        var requestURL = url
        if let token, var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comp.queryItems = (comp.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
            if let withToken = comp.url { requestURL = withToken }
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                AuthSession.handle(http: http, data: data)
                guard (200...299).contains(http.statusCode) else { return nil }
            }
            return downsample(data: data, maxPixelSize: pixelSize)
        } catch {
            return nil
        }
    }

    nonisolated private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
