//
//  NationalHpOverviewCard.swift
//  Provikart
//
//  Hlavní karta přehledu národního manažera: kolik HP celkem,
//  kolik je zavřeno / neobchodovatelné a co zbývá na prodej,
//  plus trychtýř obchodovatelné HP → otevřené dveře → fiber.
//

import SwiftUI

struct NationalHpOverviewCard: View {
    let stats: NationalLocalityStats
    let facets: NationalLocalityFacets
    var onTap: () -> Void = {}

    @State private var reveal: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var closed: Int { max(0, stats.hpClosed) }
    private var notTradable: Int { max(0, stats.hpNotTradable) }
    /// Obchodovatelné HP – z API, jinak dopočet.
    private var tradable: Int {
        stats.hpCounted > 0 ? stats.hpCounted : max(0, stats.hp - closed - notTradable)
    }
    private var total: Int { max(stats.hp, tradable + closed + notTradable) }

    private var notTradableTint: Color { Color.secondary.opacity(0.55) }

    private struct Segment: Identifiable {
        let id: String
        let title: String
        let value: Int
        let tint: Color
    }

    private var segments: [Segment] {
        [
            .init(id: "tradable", title: "Obchodovatelné", value: tradable, tint: SV.sky),
            .init(id: "closed", title: "Zavřeno", value: closed, tint: SV.coral),
            .init(id: "notTradable", title: "Neobchodovatelné", value: notTradable, tint: notTradableTint),
        ]
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                header
                segmentBar
                legend
                Divider().opacity(0.5)
                funnel
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SVCardBackground(radius: 24, tint: SV.sky))
        }
        .buttonStyle(.plain)
        .onAppear {
            guard reveal < 1 else { return }
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) { reveal = 1 }
            }
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HP CELKEM")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(total.formatted())
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("domácností v \(stats.total.formatted()) \(localityWord(stats.total))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    // MARK: - Rozpad HP

    private var segmentBar: some View {
        let parts = segments.filter { $0.value > 0 }
        let sum = max(1, parts.reduce(0) { $0 + $1.value })
        return GeometryReader { geo in
            let gaps = CGFloat(max(0, parts.count - 1)) * 3
            let usable = max(0, geo.size.width - gaps) * reveal
            HStack(spacing: 3) {
                ForEach(parts) { part in
                    Capsule()
                        .fill(part.tint)
                        .frame(width: max(0, usable * CGFloat(part.value) / CGFloat(sum)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 14)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var legend: some View {
        VStack(spacing: 10) {
            ForEach(segments) { segment in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.tint)
                        .frame(width: 10, height: 10)
                    Text(segment.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if segment.id == "closed", let count = facets.closed, count > 0 {
                        Text("· \(count.formatted()) \(localityNoun(count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(segment.value.formatted())
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text(percent(segment.value, of: total))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .opacity(segment.value > 0 ? 1 : 0.5)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Trychtýř

    private var funnel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Z obchodovatelných HP")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            funnelRow(
                title: "Otevřené dveře",
                value: stats.opened,
                pct: stats.openedPct,
                caption: "z \(tradable.formatted()) HP",
                tint: SV.accent
            )
            funnelRow(
                title: "Fiber",
                value: stats.fiberKs,
                pct: stats.penetrationPct,
                caption: "z otevřených · penetrace",
                tint: SV.lime
            )
        }
    }

    private func funnelRow(title: String, value: Int, pct: Double, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(value.formatted())
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(pctText(pct))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, pct / 100))) * reveal)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pomocné

    private func percent(_ value: Int, of whole: Int) -> String {
        guard whole > 0 else { return "0 %" }
        return pctText(Double(value) / Double(whole) * 100)
    }

    private func pctText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "cs_CZ"))) + " %"
    }

    private func localityNoun(_ count: Int) -> String {
        if count == 1 { return "lokalita" }
        if (2...4).contains(count) { return "lokality" }
        return "lokalit"
    }

    private func localityWord(_ count: Int) -> String {
        if count == 1 { return "lokalitě" }
        return "lokalitách"
    }
}
