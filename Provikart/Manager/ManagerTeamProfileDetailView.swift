//
//  ManagerTeamProfileDetailView.swift
//  Provikart
//
//  Detail týmového profilu pro manažera.
//

import SwiftUI

@MainActor
final class ManagerTeamProfileDetailViewModel: ObservableObject {
    @Published var profile: TeamProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = TeamProfileService()

    func loadProfile(id: Int, token: String?, preview: TeamProfile?) async {
        profile = preview
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            profile = try await service.fetchProfile(id: id, token: token)
            isLoading = false
        } catch {
            isLoading = false
            if profile == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ManagerTeamProfileDetailView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerTeamProfileDetailViewModel()
    let profileID: Int
    let preview: TeamProfile?

    var body: some View {
        Group {
            if let message = viewModel.errorMessage, viewModel.profile == nil {
                ContentUnavailableView {
                    Label("Profil nenalezen", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(message)
                }
            } else if let profile = viewModel.profile {
                profileContent(profile)
            } else {
                ProgressView("Načítám profil…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadProfile(id: profileID, token: authState.authToken, preview: preview)
        }
        .task {
            await viewModel.loadProfile(id: profileID, token: authState.authToken, preview: preview)
        }
    }

    private func profileContent(_ profile: TeamProfile) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard(profile)
                contactSection(profile)
                personalSection(profile)
                profileDetailsSection(profile)
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

    private func headerCard(_ profile: TeamProfile) -> some View {
        VStack(spacing: 14) {
            Group {
                if let url = profile.profileImageURL {
                    AuthenticatedProfileImageView(
                        url: url,
                        token: authState.authToken,
                        size: 88
                    )
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 88, height: 88)
                        .overlay {
                            Text(profile.initials)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .overlay {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 3)
            }

            VStack(spacing: 4) {
                Text(profile.displayName)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let roleLabel = profile.roleLabel {
                Text(roleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(detailCardBackground(tint: .blue))
    }

    private func contactSection(_ profile: TeamProfile) -> some View {
        detailSection(title: "Kontakt", icon: "envelope") {
            detailRow(label: "E-mail", value: profile.email, icon: "envelope")
            detailRow(label: "Osobní číslo", value: profile.personal_number, icon: "person.text.rectangle")
            detailRow(label: "Město", value: profile.city, icon: "mappin.and.ellipse")
        }
    }

    private func personalSection(_ profile: TeamProfile) -> some View {
        detailSection(title: "Osobní údaje", icon: "calendar") {
            detailRow(label: "Datum narození", value: formattedBirthDate(profile.birth_date), icon: "calendar")
        }
    }

    private func profileDetailsSection(_ profile: TeamProfile) -> some View {
        detailSection(title: "O profilu", icon: "person.text.rectangle") {
            detailTextBlock(label: "Zájmy", value: profile.interests, icon: "heart.text.square")
            detailTextBlock(label: "Motivace", value: profile.motivation, icon: "sparkles")
            detailTextBlock(label: "Na co si dát pozor", value: profile.watch_for, icon: "eye")
        }
    }

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(detailCardBackground(tint: .gray))
        }
    }

    private func detailRow(label: String, value: String?, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayValue(value))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func detailTextBlock(label: String, value: String?, icon: String) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Group {
            if !trimmed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(label, systemImage: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(trimmed)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Neuvedeno" : trimmed
    }

    private func formattedBirthDate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let parsers = ["yyyy-MM-dd", "dd.MM.yyyy", "d.M.yyyy"]
        let output = DateFormatter()
        output.locale = Locale(identifier: "cs_CZ")
        output.timeZone = .current
        output.dateFormat = "d. MMMM yyyy"

        for format in parsers {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = .current
            parser.dateFormat = format
            if let date = parser.date(from: raw) {
                return output.string(from: date)
            }
        }
        return raw
    }

    private func detailCardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.1), tint.opacity(0.03), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

#Preview {
    NavigationStack {
        ManagerTeamProfileDetailView(profileID: 1, preview: nil)
            .environmentObject(AuthState())
    }
}
