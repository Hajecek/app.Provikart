//
//  NationalIslandViews.swift
//  Sdílený soubor – identická kopie je v Provikart/Widget/Shared i ProvikartWidget/Shared.
//
//  Obsah Live Activity národního manažera pro všechny prezentace a varianty:
//  • Přehled sítě: ◔ hlášení | „18/24“   → čtyři dlaždice + ukazatel lokalit
//  • Hlášení:      ◔ hlášení | „18/24“   → velký prstenec, nahlášeno/chybí/nepřítomní
//  • Objednávky:   🔍 | počet ke kontrole → vytvořené/otevřené/hotové
//

import SwiftUI

typealias NationalIslandState = NationalLiveActivityAttributes.ContentState

extension NationalLiveActivityAttributes.ContentState {
    var reportProgress: Double {
        guard salesExpected > 0 else { return 0 }
        return Double(salesReported) / Double(salesExpected)
    }

    var reportText: String {
        salesExpected > 0 ? "\(salesReported)/\(salesExpected)" : "–"
    }

    var localitiesProgress: Double {
        guard localitiesTotal > 0 else { return 0 }
        return Double(localitiesDone) / Double(localitiesTotal)
    }

    var salesMissing: Int { max(salesExpected - salesReported, 0) }

    var created: Int { ordersCreated ?? 0 }
    var open: Int { ordersOpen ?? 0 }
    var completed: Int { ordersCompleted ?? 0 }
    var ordersAll: Int { max(created + open + completed, 1) }
}

extension NationalLiveActivityKind {
    var islandTint: Color {
        switch self {
        case .overview: return IslandPalette.violet
        case .reports: return IslandPalette.mint
        case .orders: return IslandPalette.amber
        }
    }
}

// MARK: - Compact a minimal

struct NationalIslandCompactLeading: View {
    var state: NationalIslandState

    var body: some View {
        switch state.resolvedKind {
        case .overview, .reports:
            IslandMiniRing(progress: state.reportProgress, tint: IslandPalette.mint) {
                Image(systemName: "mappin")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(IslandPalette.mint)
            }
        case .orders:
            Image(systemName: state.ordersToCheck > 0 ? "doc.text.magnifyingglass" : "checkmark.seal.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IslandPalette.amber)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

struct NationalIslandCompactTrailing: View {
    var state: NationalIslandState

    var body: some View {
        Group {
            switch state.resolvedKind {
            case .overview, .reports:
                IslandFixedWidthText(text: state.reportText, probe: "00/00", numericValue: Double(state.salesReported))
                    .foregroundStyle(IslandPalette.mint)
            case .orders:
                IslandFixedWidthText(text: "\(state.ordersToCheck)", probe: "000", numericValue: Double(state.ordersToCheck))
                    .foregroundStyle(IslandPalette.amber)
            }
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
    }
}

struct NationalIslandMinimal: View {
    var state: NationalIslandState

    var body: some View {
        let showOrders = state.resolvedKind == .orders || (state.resolvedKind == .overview && state.ordersToCheck > 0)
        IslandMiniRing(
            progress: showOrders ? Double(state.ordersToCheck) / Double(state.ordersAll) : state.reportProgress,
            tint: showOrders ? IslandPalette.amber : IslandPalette.mint,
            size: 24,
            lineWidth: 3
        ) {
            Text("\(showOrders ? state.ordersToCheck : state.salesReported)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(state.ordersToCheck + state.salesReported)))
        }
    }
}

// MARK: - Rozbalený Island

struct NationalIslandExpandedLeading: View {
    var state: NationalIslandState

    var body: some View {
        let kind = state.resolvedKind
        IslandBrandHeader(
            symbol: kind.symbolName,
            title: kind == .overview ? "Síť" : (kind == .reports ? "Hlášení" : "Objednávky"),
            subtitle: state.dayLabel ?? "Dnes",
            tint: kind.islandTint
        )
    }
}

struct NationalIslandExpandedTrailing: View {
    var state: NationalIslandState
    var inline = false

    var body: some View {
        switch state.resolvedKind {
        case .overview:
            IslandHeadlineValue(text: "\(IslandFormat.percent(state.reportProgress)) %", value: state.reportProgress,
                                caption: "nahlášeno", color: IslandPalette.mint, inline: inline)
        case .reports:
            IslandHeadlineValue(text: state.reportText, value: Double(state.salesReported),
                                caption: "obchodníků", color: IslandPalette.mint, inline: inline)
        case .orders:
            IslandHeadlineValue(text: "\(state.ordersToCheck)", value: Double(state.ordersToCheck),
                                caption: "ke kontrole", color: IslandPalette.amber, inline: inline)
        }
    }
}

struct NationalIslandExpandedBottom: View {
    var state: NationalIslandState
    var ringSize: CGFloat = 36

    var body: some View {
        switch state.resolvedKind {
        case .overview:
            VStack(spacing: 10) {
                NationalTiles(state: state, ringSize: ringSize)
                NationalLocalitiesBar(state: state)
            }
        case .reports:
            NationalReportsBody(state: state, ringSize: ringSize + 22)
        case .orders:
            NationalOrdersBody(state: state, ringSize: ringSize + 4)
        }
    }
}

// MARK: - Lock Screen (obsah karty)

struct NationalLockCard: View {
    var state: NationalIslandState
    var isStale: Bool

    /// Lock Screen má omezenou výšku (~160 pt) – rozložení je nižší než v rozbaleném Islandu.
    var body: some View {
        let kind = state.resolvedKind
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(kind.islandTint)
                    Text(kind.title)
                    Text("· \(statusLabel)")
                        .foregroundStyle(isStale ? IslandPalette.tertiary : IslandPalette.secondary)
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                NationalIslandExpandedTrailing(state: state, inline: true)
            }
            switch kind {
            case .overview:
                NationalTiles(state: state, ringSize: 30)
                if state.localitiesTotal > 0 {
                    IslandBarMeter(
                        progress: state.localitiesProgress,
                        colors: [IslandPalette.sky, IslandPalette.violet, IslandPalette.violet],
                        segments: 34,
                        height: 8
                    )
                }
            case .reports:
                NationalReportsBody(state: state, ringSize: 60)
            case .orders:
                NationalOrdersBody(state: state, ringSize: 30)
            }
        }
        .foregroundStyle(.white)
    }

    private var statusLabel: String {
        if isStale { return "neaktuální" }
        if let day = state.dayLabel, !day.isEmpty { return day }
        return "dnes"
    }
}

// MARK: - Části

struct NationalTiles: View {
    var state: NationalIslandState
    var ringSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            IslandGaugeTile(
                symbol: "mappin.and.ellipse",
                value: state.reportText,
                numericValue: Double(state.salesReported),
                caption: "Hlášení",
                tint: IslandPalette.mint,
                style: .ring(state.reportProgress),
                ringSize: ringSize
            )
            IslandGaugeTile(
                symbol: state.ordersToCheck > 0 ? "doc.text.magnifyingglass" : "checkmark",
                value: "\(state.ordersToCheck)",
                numericValue: Double(state.ordersToCheck),
                caption: "Ke kontrole",
                tint: IslandPalette.amber,
                style: .alert(state.ordersToCheck > 0),
                ringSize: ringSize
            )
            IslandGaugeTile(
                symbol: "flag.checkered",
                value: "\(IslandFormat.percent(state.localitiesProgress)) %",
                numericValue: state.localitiesProgress,
                caption: "Lokality",
                tint: IslandPalette.violet,
                style: .ring(state.localitiesProgress),
                ringSize: ringSize
            )
            IslandGaugeTile(
                symbol: state.unassignedLocalities > 0 ? "person.crop.circle.badge.questionmark" : "person.crop.circle.badge.checkmark",
                value: "\(state.unassignedLocalities)",
                numericValue: Double(state.unassignedLocalities),
                caption: "Bez manaž.",
                tint: IslandPalette.coral,
                style: .alert(state.unassignedLocalities > 0),
                ringSize: ringSize
            )
        }
    }
}

struct NationalLocalitiesBar: View {
    var state: NationalIslandState

    var body: some View {
        if state.localitiesTotal > 0 {
            VStack(spacing: 5) {
                IslandBarMeter(
                    progress: state.localitiesProgress,
                    colors: [IslandPalette.sky, IslandPalette.violet, IslandPalette.violet],
                    segments: 32,
                    height: 12
                )
                HStack {
                    Text("\(state.localitiesDone.formatted()) z \(state.localitiesTotal.formatted()) lokalit hotovo")
                        .contentTransition(.numericText(value: Double(state.localitiesDone)))
                    Spacer(minLength: 4)
                    if state.salesMissing > 0 {
                        Text("chybí \(state.salesMissing) hlášení")
                            .foregroundStyle(IslandPalette.coral)
                            .contentTransition(.numericText(value: Double(state.salesMissing)))
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandPalette.secondary)
                .lineLimit(1)
                .islandAnimation(value: state.salesMissing)
            }
        }
    }
}

struct NationalReportsBody: View {
    var state: NationalIslandState
    var ringSize: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                IslandRing(progress: state.reportProgress, tint: IslandPalette.mint, lineWidth: ringSize * 0.12)
                VStack(spacing: -2) {
                    Text("\(IslandFormat.percent(state.reportProgress))")
                        .font(.system(size: ringSize * 0.3, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: state.reportProgress))
                    Text("%")
                        .font(.system(size: ringSize * 0.16, weight: .bold))
                        .foregroundStyle(IslandPalette.secondary)
                }
                .foregroundStyle(.white)
            }
            .frame(width: ringSize, height: ringSize)

            VStack(spacing: 6) {
                IslandStatRow(symbol: "checkmark.circle.fill", title: "Nahlášeno", value: "\(state.salesReported)",
                              numericValue: Double(state.salesReported), tint: IslandPalette.mint)
                IslandStatRow(symbol: "clock.badge.exclamationmark", title: "Chybí", value: "\(state.salesMissing)",
                              numericValue: Double(state.salesMissing), tint: IslandPalette.coral)
                IslandStatRow(symbol: "moon.zzz.fill", title: "Nepřítomní", value: "\(state.salesAbsent ?? 0)",
                              numericValue: Double(state.salesAbsent ?? 0), tint: IslandPalette.sky)
            }
        }
    }
}

struct NationalOrdersBody: View {
    var state: NationalIslandState
    var ringSize: CGFloat

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                tile("Vytvořeno", state.created, IslandPalette.amber, "doc.badge.plus")
                tile("Otevřeno", state.open, IslandPalette.sky, "envelope.open.fill")
                tile("Hotovo", state.completed, IslandPalette.mint, "checkmark")
            }
            // Poměr stavů v jednom proužku – části se při změně plynule posunou.
            GeometryReader { geo in
                let total = CGFloat(state.ordersAll)
                HStack(spacing: 3) {
                    segment(IslandPalette.amber, width: geo.size.width * CGFloat(state.created) / total)
                    segment(IslandPalette.sky, width: geo.size.width * CGFloat(state.open) / total)
                    segment(IslandPalette.mint, width: geo.size.width * CGFloat(state.completed) / total)
                    Spacer(minLength: 0)
                }
                .islandAnimation(value: [state.created, state.open, state.completed])
            }
            .frame(height: 8)
        }
    }

    private func tile(_ title: String, _ value: Int, _ tint: Color, _ symbol: String) -> some View {
        IslandGaugeTile(
            symbol: symbol,
            value: "\(value)",
            numericValue: Double(value),
            caption: title,
            tint: tint,
            style: .ring(Double(value) / Double(state.ordersAll)),
            ringSize: ringSize
        )
    }

    private func segment(_ color: Color, width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: max(width - 3, 0))
    }
}

// MARK: - Ukázková data (náhled ve výběru)

extension NationalLiveActivityAttributes.ContentState {
    static func sample(kind: NationalLiveActivityKind) -> Self {
        Self(
            salesReported: 18, salesExpected: 24, ordersToCheck: 7,
            localitiesDone: 412, localitiesTotal: 960, unassignedLocalities: 23,
            dayLabel: "21. listopadu", kind: kind, salesAbsent: 3,
            ordersCreated: 4, ordersOpen: 3, ordersCompleted: 11
        )
    }
}
