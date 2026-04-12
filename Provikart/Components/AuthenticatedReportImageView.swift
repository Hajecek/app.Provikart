//
//  AuthenticatedReportImageView.swift
//  Provikart
//
//  Přílohy reportů často vyžadují stejnou autentizaci jako API (Bearer + token v query).
//  AsyncImage tyto hlavičky neposílá — proto nahrazeno vlastním načtením.
//

import SwiftUI
import UIKit

enum ReportAttachmentImageLoader {
    /// Načte obrázek z URL; při neprázdném tokenu přidá query `token` a hlavičku Authorization.
    static func loadUIImage(from url: URL, token: String?) async -> UIImage? {
        var requestURL = url
        if let token, !token.isEmpty, var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let existing = comp.queryItems ?? []
            let hasTokenParam = existing.contains { $0.name == "token" }
            if !hasTokenParam {
                comp.queryItems = existing + [URLQueryItem(name: "token", value: token)]
                if let withToken = comp.url { requestURL = withToken }
            }
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 90
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

/// Náhled fotky v detailu reportu (nahrazuje AsyncImage).
struct ReportAttachmentThumbnailView: View {
    let url: URL
    var token: String?
    var onTap: (() -> Void)?

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if loadFailed {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 80)
                    .overlay {
                        VStack(spacing: 8) {
                            Label("Obrázek se nepodařilo načíst", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Zkusit znovu") {
                                Task { await load() }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 160)
                    .overlay { ProgressView() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .task(id: "\(url.absoluteString)|\(token ?? "")") { await load() }
    }

    private func load() async {
        await MainActor.run {
            loadFailed = false
            image = nil
        }
        let img = await ReportAttachmentImageLoader.loadUIImage(from: url, token: token)
        await MainActor.run {
            image = img
            loadFailed = (img == nil)
        }
    }
}
