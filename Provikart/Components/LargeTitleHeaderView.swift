//
//  LargeTitleHeaderView.swift
//  Provikart
//

import SwiftUI

/// Načte obrázek z URL s volitelným Bearer tokenem (pro /auth/images/).
struct AuthenticatedProfileImageView: View {
    let url: URL
    var fallbackURL: URL? = nil
    var token: String?
    let size: CGFloat = 44

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if loadFailed {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        loadFailed = false
        image = nil
        let urlsToTry = [url] + (fallbackURL.map { [$0] } ?? [])
        for tryURL in urlsToTry {
            var requestURL = tryURL
            if let token, var comp = URLComponents(url: tryURL, resolvingAgainstBaseURL: false) {
                let existing = comp.queryItems ?? []
                comp.queryItems = existing + [URLQueryItem(name: "token", value: token)]
                if let withToken = comp.url { requestURL = withToken }
            }
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            print("[Avatar] Načítám: \(requestURL.absoluteString.prefix(80))…, token: \(token != nil ? "ano" : "ne")")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let code = http?.statusCode ?? -1
                if (200...299).contains(code), let img = UIImage(data: data) {
                    print("[Avatar] OK – načteno \(data.count) bajtů z \(tryURL.absoluteString)")
                    await MainActor.run {
                        image = img
                    }
                    return
                }
                print("[Avatar] HTTP \(code) pro \(tryURL.absoluteString), zkouším další URL…")
            } catch {
                print("[Avatar] Chyba pro \(tryURL.absoluteString): \(error.localizedDescription)")
            }
        }
        loadFailed = true
    }
}

/// Vlastní hlavička: velký nadpis vlevo, ikona profilu vpravo, v jednom řádku (pro Domů, Vyhledávání, Nastavení).
struct PageHeaderBar: View {
    @EnvironmentObject private var authState: AuthState
    let title: String
    var onProfileTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer(minLength: 0)
            Button(action: { onProfileTap?() }) {
                profileImageView
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        // Odstraněno pozadí pro plnou transparentnost
        // .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var profileImageView: some View {
        if let url = authState.currentUser?.profileImageURL {
            AuthenticatedProfileImageView(
                url: url,
                token: authState.authToken
            )
            .frame(width: 44, height: 44)
        } else {
            let _ = print("[Avatar] Žádný currentUser nebo profileImageURL – currentUser: \(authState.currentUser != nil), profile_image: \(authState.currentUser?.profile_image ?? "nil")")
            Image(systemName: "person.circle.fill")
                .font(.title2)
        }
    }
}

/// Systémový toolbar s nadpisem a ikonou profilu (pouze pro stránku Profil).
struct LargeTitleHeaderView<Content: View>: View {
    let title: String
    var onProfileTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { onProfileTap?() }) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

