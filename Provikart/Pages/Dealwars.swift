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

// MARK: - Level detail

struct DealwarsLevelDetailView: View {
    @EnvironmentObject private var authState: AuthState

    let initialLevel: DealwarsLevelInfo?

    @State private var level: DealwarsLevelInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = DealwarsSeasonService()

    private let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
    private let orange = Color(red: 0.97, green: 0.58, blue: 0.12)

    var body: some View {
        Group {
            if isLoading && level == nil {
                ProgressView("Načítám level…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, level == nil {
                ContentUnavailableView {
                    Label("Nepodařilo se načíst level", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Zkusit znovu") {
                        Task { await loadLevel() }
                    }
                }
            } else if let level {
                ScrollView {
                    VStack(spacing: 28) {
                        heroSection(level)
                        progressSection(level)
                        statsSection(level)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView {
                    Label("Level", systemImage: "star.circle")
                } description: {
                    Text("Zatím nemáme data o tvém levelu.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                Color(uiColor: .systemGroupedBackground)
                DealwarsLevelTopGlow()
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Tvůj level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if level == nil {
                level = initialLevel
            }
            await loadLevel()
        }
        .refreshable { await loadLevel() }
    }

    private func heroSection(_ level: DealwarsLevelInfo) -> some View {
        VStack(spacing: 10) {
            Text("LEVEL")
                .font(.caption.weight(.bold))
                .tracking(3)
                .foregroundStyle(gold.opacity(0.9))

            Text("\(level.level)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [gold, orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .monospacedDigit()
                .shadow(color: orange.opacity(0.45), radius: 18, y: 6)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("\(level.totalPoints) bodů celkem")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func progressSection(_ level: DealwarsLevelInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Postup k levelu \(level.level + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(level.levelProgressPct.rounded())) %")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(orange)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [gold, orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * level.progressFraction))
                        .shadow(color: orange.opacity(0.35), radius: 6, y: 1)
                }
            }
            .frame(height: 14)

            HStack {
                Text("\(level.pointsIntoLevel) / \(level.pointsForNextLevel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("ještě \(level.pointsToNextLevel)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(orange)
                    .monospacedDigit()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(gold.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func statsSection(_ level: DealwarsLevelInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statTile(title: "Celkem", value: "\(level.totalPoints)", subtitle: "bodů")
                statTile(title: "V levelu", value: "\(level.pointsIntoLevel)", subtitle: "bodů")
            }
            HStack(spacing: 12) {
                statTile(title: "Na další", value: "\(level.pointsForNextLevel)", subtitle: "bodů")
                statTile(title: "Zbývá", value: "\(level.pointsToNextLevel)", subtitle: "bodů")
            }
        }
    }

    private func statTile(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func loadLevel() async {
        await MainActor.run {
            if level == nil {
                isLoading = true
            }
            errorMessage = nil
        }
        do {
            let payload = try await service.fetchSeason(
                token: authState.authToken,
                season: nil,
                scope: "team"
            )
            await MainActor.run {
                level = payload.myLevel ?? level
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if level == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct DealwarsLevelTopGlow: View {
    private let logoOrange = Color(red: 0.97, green: 0.58, blue: 0.12)
    private let logoGold = Color(red: 0.98, green: 0.69, blue: 0.23)
    private let logoPurple = Color(red: 0.30, green: 0.05, blue: 0.22)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: logoOrange.opacity(0.34), location: 0),
                        .init(color: logoGold.opacity(0.22), location: 0.28),
                        .init(color: logoGold.opacity(0.08), location: 0.55),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 360)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                logoGold.opacity(0.45),
                                logoOrange.opacity(0.18),
                                .clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: width * 0.55
                        )
                    )
                    .frame(width: width * 1.1, height: 220)
                    .offset(y: -40)

                Ellipse()
                    .fill(logoPurple.opacity(0.18))
                    .frame(width: width * 0.7, height: 160)
                    .blur(radius: 40)
                    .offset(x: width * 0.18, y: 20)
            }
            .frame(width: width, alignment: .top)
        }
        .frame(height: 360)
    }
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
