//
//  ManagerTeamProfilesView.swift
//  Provikart
//
//  Přehled týmových profilů pro manažera.
//

import SwiftUI

@MainActor
final class ManagerTeamProfilesViewModel: ObservableObject {
    @Published var profiles: [TeamProfile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = TeamProfileService()

    func loadProfiles(token: String?, currentUserId: Int?) async {
        guard let token, !token.isEmpty else {
            profiles = []
            errorMessage = "Nejste přihlášeni."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await service.fetchProfiles(token: token, includeSelf: false)
            profiles = Self.teamMembersOnly(fetched, currentUserId: currentUserId)
                .sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            isLoading = false
        } catch {
            isLoading = false
            guard !Self.isCancellation(error) else { return }
            // Při chybě nemažeme stávající data (např. cancel z pull-to-refresh).
            if profiles.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    private static func teamMembersOnly(_ profiles: [TeamProfile], currentUserId: Int?) -> [TeamProfile] {
        profiles.filter { profile in
            if profile.isManagerRole {
                return false
            }
            if let currentUserId, profile.id == currentUserId {
                return false
            }
            return true
        }
    }

    func filteredProfiles(search: String) -> [TeamProfile] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.displayName.lowercased().contains(query)
                || (profile.username?.lowercased().contains(query) ?? false)
                || (profile.email?.lowercased().contains(query) ?? false)
                || (profile.city?.lowercased().contains(query) ?? false)
        }
    }

    func filledProfilesCount() -> Int {
        profiles.filter { $0.hasProfileContent }.count
    }
}

private extension TeamProfile {
    var hasProfileContent: Bool {
        [city, interests, motivation, watch_for, birth_date]
            .contains { !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    }

    var isManagerRole: Bool {
        role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "manager"
    }
}

struct ManagerTeamProfilesView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerTeamProfilesViewModel()
    @State private var searchText = ""
    @State private var selectedProfile: TeamProfile?
    @State private var isLocationsSheetPresented = false

    private var filteredProfiles: [TeamProfile] {
        viewModel.filteredProfiles(search: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    loadingView
                } else if let message = viewModel.errorMessage, viewModel.profiles.isEmpty {
                    errorView(message)
                } else if viewModel.profiles.isEmpty {
                    emptyTeamView
                } else {
                    mainContent
                }
            }
            .background { ManagerScreenBackground() }
            .navigationTitle("Tým")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ManagerAddReportToolbarButton()
                    Button {
                        isLocationsSheetPresented = true
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .accessibilityLabel("Lokality týmu")
                    ManagerNotificationsBellButton()
                    ProfileBarButton()
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Hledat člena týmu")
            .navigationDestination(item: $selectedProfile) { profile in
                ManagerTeamProfileDetailView(profileID: profile.id, preview: profile)
                    .environmentObject(authState)
            }
            .sheet(isPresented: $isLocationsSheetPresented) {
                ManagerLocationsSheetView()
                    .environmentObject(authState)
            }
            .refreshable {
                await viewModel.loadProfiles(token: authState.authToken, currentUserId: authState.currentUser?.id)
            }
            .task {
                await viewModel.loadProfiles(token: authState.authToken, currentUserId: authState.currentUser?.id)
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard
                membersSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profily týmu")
                .font(.headline)
            Text("\(viewModel.profiles.count) členů bez manažera")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                summaryBadge(
                    title: "Vyplněné profily",
                    value: viewModel.filledProfilesCount(),
                    tint: .green,
                    icon: "checkmark.circle.fill"
                )
                summaryBadge(
                    title: "Bez detailu",
                    value: max(viewModel.profiles.count - viewModel.filledProfilesCount(), 0),
                    tint: .orange,
                    icon: "person.crop.circle.badge.questionmark"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground(tint: .blue))
    }

    private func summaryBadge(title: String, value: Int, tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.subheadline.weight(.bold))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Členové")
                    .font(.headline)
                Spacer()
                Text("\(filteredProfiles.count) z \(viewModel.profiles.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if filteredProfiles.isEmpty {
                ContentUnavailableView {
                    Label("Žádné výsledky", systemImage: "magnifyingglass")
                } description: {
                    Text("Zkuste upravit hledaný výraz.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredProfiles) { profile in
                        Button {
                            selectedProfile = profile
                        } label: {
                            profileRow(profile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: TeamProfile) -> some View {
        HStack(spacing: 12) {
            profileAvatar(profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let city = profile.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                    Label(city, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let roleLabel = profile.roleLabel {
                Text(roleLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(cardBackground(tint: profile.hasProfileContent ? .green : .gray))
    }

    private func profileAvatar(_ profile: TeamProfile) -> some View {
        Group {
            if let url = profile.profileImageURL {
                AuthenticatedProfileImageView(
                    url: url,
                    token: authState.authToken,
                    size: 46
                )
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Text(profile.initials)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
            }
        }
        .overlay {
            Circle()
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 2)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Načítám profily…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst profily", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Zkusit znovu") {
                Task {
                    await viewModel.loadProfiles(token: authState.authToken, currentUserId: authState.currentUser?.id)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyTeamView: some View {
        ContentUnavailableView(
            "Žádní členové týmu",
            systemImage: "person.3",
            description: Text("Manažer nemá k dispozici žádné profily týmu.")
        )
    }

    private func cardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.14), tint.opacity(0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

#Preview {
    ManagerTeamProfilesView()
        .environmentObject(AuthState())
}
