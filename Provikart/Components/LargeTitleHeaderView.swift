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
    /// Jedna velikost pro layout i výřez — vyhni se `.frame` zvenku (jinak se špatně ořezává).
    var size: CGFloat = 44

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var imageURL: URL?
    @State private var loadFailed = false

    private var pixelSize: CGFloat { size * max(displayScale, 2) }

    var body: some View {
        Group {
            if let image = (imageURL == url ? image : nil) ?? ProfileImageLoader.shared.cachedImage(url: url, pixelSize: pixelSize) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else if loadFailed {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: size * 0.72))
                }
                .frame(width: size, height: size, alignment: .center)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                    ProgressView()
                        .scaleEffect(min(1, size / 28))
                }
                .frame(width: size, height: size, alignment: .center)
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .contentShape(Circle())
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let loader = ProfileImageLoader.shared
        let pixelSize = pixelSize
        if let cached = loader.cachedImage(url: url, pixelSize: pixelSize) {
            image = cached
            imageURL = url
            loadFailed = false
            return
        }
        // Nemažeme už zobrazený obrázek – žádné problikávání spinneru při překreslení.
        loadFailed = false
        let urlsToTry = [url] + (fallbackURL.map { [$0] } ?? [])
        let loaded = await loader.image(urls: urlsToTry, token: token, pixelSize: pixelSize)
        guard !Task.isCancelled else { return }
        if let loaded {
            image = loaded
            imageURL = url
        } else if image == nil || imageURL != url {
            loadFailed = true
        }
    }
}

/// Tlačítko profilu do toolbaru – použití např. .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileBarButton() } }
struct ProfileBarButton: View {
    @EnvironmentObject private var authState: AuthState

    /// Systémový toolbar má výšku ~44 pt; avatar vycentrovaný uvnitř.
    private let toolbarAvatarSize: CGFloat = 30

    var body: some View {
        NavigationLink {
            ProfileView()
                .environmentObject(authState)
        } label: {
            Group {
                if let url = authState.currentUser?.profileImageURL {
                    AuthenticatedProfileImageView(
                        url: url,
                        token: authState.authToken,
                        size: toolbarAvatarSize
                    )
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: toolbarAvatarSize, height: toolbarAvatarSize)
                        .contentShape(Circle())
                }
            }
            .frame(width: 44, height: 44, alignment: .center)
            .contentShape(Circle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
    }
}

/// Logo Provikart pro navigaci – velké (jako large title) nebo kompaktní (při scrollu).
struct ProvikartBrandLogoView: View {
    enum Style {
        case compact
        case large

        var size: CGFloat {
            switch self {
            case .compact: 26
            case .large: 34
            }
        }
    }

    var style: Style = .large

    var body: some View {
        Image("logo")
            .resizable()
            .scaledToFill()
            .frame(width: style.size, height: style.size)
            .clipShape(Circle())
            .accessibilityLabel("Provikart")
    }
}

/// Vlastní hlavička: velký nadpis vlevo, ikona profilu vpravo (např. pro fullscreen flow bez NavigationStack).
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
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var profileImageView: some View {
        if let url = authState.currentUser?.profileImageURL {
            AuthenticatedProfileImageView(
                url: url,
                token: authState.authToken,
                size: 44
            )
        } else {
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
