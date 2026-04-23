//
//  Dealwars.swift
//  Provikart
//
//

import SwiftUI

struct DealwarsView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSeason = ""
    @State private var players: [DealwarsPlayer] = []
    @State private var teamPlayers: [DealwarsTeamPlayer] = []

    private let service = DealwarsSeasonService()

    private var sortedPlayers: [DealwarsPlayer] {
        players.sorted { left, right in
            if left.rank == right.rank {
                return left.points > right.points
            }
            // Pokud API pošle rank 0/negativní, posunout je na konec.
            let leftRank = left.rank > 0 ? left.rank : Int.max
            let rightRank = right.rank > 0 ? right.rank : Int.max
            return leftRank < rightRank
        }
    }

    private var topThree: [DealwarsPlayer] {
        Array(sortedPlayers.prefix(3))
    }

    private var topPlayerIDs: Set<String> {
        Set(topThree.map(\.id))
    }

    private var otherPlayers: [DealwarsPlayer] {
        sortedPlayers.filter { !topPlayerIDs.contains($0.id) }
    }

    private var teamPlayerById: [Int: DealwarsTeamPlayer] {
        Dictionary(uniqueKeysWithValues: teamPlayers.map { ($0.sellerId, $0) })
    }

    private var weekOptions: [WeekOption] {
        WeekOption.make(lastWeeks: 12, nextWeeks: 8)
    }

    private var selectedWeekOption: WeekOption? {
        weekOptions.first(where: { $0.seasonCode == selectedSeason })
    }

    private var selectedWeekIndex: Int? {
        weekOptions.firstIndex(where: { $0.seasonCode == selectedSeason })
    }

    var body: some View {
        Group {
            if isLoading && players.isEmpty {
                ProgressView("Načítám Deal Wars…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Nepodařilo se načíst žebříček", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Zkusit znovu") {
                        Task { await loadSeason() }
                    }
                }
            } else if sortedPlayers.isEmpty {
                ContentUnavailableView {
                    Label("Deal Wars", systemImage: "trophy")
                } description: {
                    Text("Na tomto se momentálně pracuje")
                }
            } else {
                List {
                    if !topThree.isEmpty {
                        Section {
                            podiumView
                        } header: {
                            Text("Vítězové")
                                .textCase(nil)
                        }
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        otherPlayersTableHeader
                        ForEach(otherPlayers) { player in
                            otherPlayersTableRow(player)
                        }
                    } header: {
                        Text("Ostatní hráči")
                            .textCase(nil)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Dealwars")
                        .font(.headline)
                    if let selectedWeekOption {
                        Text(selectedWeekOption.rangeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                weekFilterMenu
            }
        }
        .task(id: selectedSeason) {
            if selectedSeason.isEmpty {
                selectedSeason = WeekOption.currentSeasonCode()
                return
            }

            await loadSeason()

            // Průběžná aktualizace žebříčku (pseudo realtime).
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if Task.isCancelled { break }
                await loadSeason(silent: true)
            }
        }
        .refreshable { await loadSeason() }
    }

    private var weekFilterMenu: some View {
        Menu {
            Button {
                shiftWeek(by: -1)
            } label: {
                Label("Předchozí týden", systemImage: "chevron.left")
            }
            .disabled((selectedWeekIndex ?? 0) <= 0)

            Button {
                shiftWeek(by: 1)
            } label: {
                Label("Další týden", systemImage: "chevron.right")
            }
            .disabled((selectedWeekIndex ?? weekOptions.count - 1) >= weekOptions.count - 1)

            Divider()

            ForEach(weekOptions) { week in
                Button {
                    selectedSeason = week.seasonCode
                } label: {
                    HStack {
                        Text(week.label)
                        if week.seasonCode == selectedSeason {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selectedSeason.isEmpty ? "Týden" : selectedSeason, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        }
    }

    private var podiumView: some View {
        let first = topThree.first(where: { $0.rank == 1 }) ?? topThree.first
        let second = topThree.first(where: { $0.rank == 2 })
        let third = topThree.first(where: { $0.rank == 3 })

        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.yellow.opacity(0.16),
                            Color.orange.opacity(0.08),
                            Color(uiColor: .secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                )

            HStack(alignment: .bottom, spacing: 12) {
                podiumColumn(player: second, place: 2, title: "2. místo", height: 90, color: .gray.opacity(0.88))
                podiumColumn(player: first, place: 1, title: "1. místo", height: 132, color: .yellow.opacity(0.95))
                podiumColumn(player: third, place: 3, title: "3. místo", height: 74, color: Color(red: 0.76, green: 0.51, blue: 0.35))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func podiumColumn(player: DealwarsPlayer?, place: Int, title: String, height: CGFloat, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let player {
                playerAvatar(player, size: 56)
                Text(player.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                Text(pointsString(player.points))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 56, height: 56)
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("0 b")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .shadow(color: color.opacity(place == 1 ? 0.35 : 0.18), radius: place == 1 ? 9 : 4, y: 3)
                if place == 1 {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.top, 9)
                }
                Text("\(place)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .frame(width: 90, height: height)
        }
    }

    private var otherPlayersTableHeader: some View {
        HStack(spacing: 12) {
            Text("Pořadí")
                .font(.caption.weight(.semibold))
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)

            Text("Hráč")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Body")
                .font(.caption.weight(.semibold))
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func otherPlayersTableRow(_ player: DealwarsPlayer) -> some View {
        HStack(spacing: 12) {
            Text(player.rank > 0 ? "#\(player.rank)" : "—")
                .font(.subheadline.weight(.semibold))
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)

            playerAvatar(player, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Text(pointsString(player.points))
                .font(.subheadline.weight(.semibold))
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func playerAvatar(_ player: DealwarsPlayer, size: CGFloat) -> some View {
        if let url = player.resolvedProfileURL ?? fallbackAvatarURL(for: player) {
            AuthenticatedProfileImageView(
                url: url,
                token: authState.authToken,
                size: size
            )
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private func fallbackAvatarURL(for player: DealwarsPlayer) -> URL? {
        guard let userId = player.userId, let teamPlayer = teamPlayerById[userId] else { return nil }
        guard let raw = teamPlayer.sellerAvatarURL else { return nil }
        return DealwarsPlayer.normalizedURL(from: raw)
    }

    private func pointsString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0") b"
    }

    private func loadSeason(silent: Bool = false) async {
        await MainActor.run {
            if !silent {
                isLoading = true
                errorMessage = nil
            }
        }
        do {
            let payload = try await service.fetchSeason(
                token: authState.authToken,
                season: selectedSeason.isEmpty ? nil : selectedSeason,
                scope: "team"
            )
            await MainActor.run {
                players = payload.leaderboard
                teamPlayers = payload.teamPlayers
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func shiftWeek(by delta: Int) {
        guard let current = selectedWeekIndex else { return }
        let next = current + delta
        guard weekOptions.indices.contains(next) else { return }
        selectedSeason = weekOptions[next].seasonCode
    }
}

#Preview {
    DealwarsView()
}

private struct WeekOption: Identifiable {
    let seasonCode: String
    let startDate: Date
    let endDate: Date

    var id: String { seasonCode }

    var label: String { seasonCode }

    var rangeText: String {
        "\(Self.shortDateFormatter.string(from: startDate)) - \(Self.shortDateFormatter.string(from: endDate))"
    }

    static func currentSeasonCode(reference: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let year = calendar.component(.yearForWeekOfYear, from: reference)
        let week = calendar.component(.weekOfYear, from: reference)
        return String(format: "%04d-W%02d", year, week)
    }

    static func make(lastWeeks: Int, nextWeeks: Int, reference: Date = Date()) -> [WeekOption] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference

        var output: [WeekOption] = []
        for offset in stride(from: nextWeeks, through: -lastWeeks, by: -1) {
            guard let weekDate = calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: weekDate) else { continue }
            let year = calendar.component(.yearForWeekOfYear, from: weekDate)
            let week = calendar.component(.weekOfYear, from: weekDate)
            let seasonCode = String(format: "%04d-W%02d", year, week)
            let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.start
            output.append(
                WeekOption(
                    seasonCode: seasonCode,
                    startDate: interval.start,
                    endDate: end
                )
            )
        }
        return output
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. M. yyyy"
        return formatter
    }()
}
