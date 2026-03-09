//
//  WatchProfileImageView.swift
//  ProvikartWatch Watch App
//
//  Načte profilový obrázek s Bearer tokenem (endpoint vyžaduje autentizaci).
//

import SwiftUI
import WatchKit

struct WatchProfileImageView: View {
    let url: URL
    let token: String?
    var size: CGFloat = 28

    @State private var imageData: Data?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if loadFailed {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: size * 0.85))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(.quaternary)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        loadFailed = false
        imageData = nil

        var requestURL = url
        if let token, var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let existing = comp.queryItems ?? []
            comp.queryItems = existing + [URLQueryItem(name: "token", value: token)]
            if let withToken = comp.url { requestURL = withToken }
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200...299).contains(code), UIImage(data: data) != nil {
                imageData = data
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }
}
