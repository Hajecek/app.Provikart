//
//  LiveActivityIslandKit.swift
//  Sdílený soubor – identická kopie je v Provikart/Widget/Shared i ProvikartWidget/Shared
//  (aplikace z nich kreslí živý náhled ve výběru aktivity). Upravujte obě kopie stejně.
//
//  Stavebnice pro Live Activity všech rolí (uživatel, manažer, národní manažer).
//
//  Podle Apple HIG „Live Activities“ a „Animating data updates in widgets and Live Activities“:
//  • Dynamic Island má vždy černé neprůhledné pozadí – barvu nese obsah (výrazné akcenty).
//  • Compact leading + trailing se čtou jako jedna informace, jsou úzké a těsně u kamery.
//  • Minimal ukazuje živá data (ne jen logo) a vejde se do kruhu o průměru 28 pt.
//  • Expanded je zvětšená verze compactu, obsah obepíná kameru, okraje jsou soustředné.
//  • Animace maximálně 2 s; na Always-On (isLuminanceReduced) se neanimuje.
//  • Čísla mění obsah přes .contentTransition(.numericText), prvky přes .transition.
//  • Lock Screen: standardní okraj 14 pt, vlastní pozadí s dostatečným kontrastem.
//

import SwiftUI
import WidgetKit

// MARK: - Barvy

enum IslandPalette {
    static let yellow = Color(red: 251.0 / 255, green: 191.0 / 255, blue: 79.0 / 255)
    static let ink = Color(red: 0.09, green: 0.08, blue: 0.06)
    static let amber = Color(red: 1.00, green: 0.62, blue: 0.20)
    static let mint = Color(red: 0.20, green: 0.84, blue: 0.60)
    static let violet = Color(red: 0.62, green: 0.52, blue: 1.00)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.48)
    static let sky = Color(red: 0.36, green: 0.66, blue: 1.00)

    static let track = Color.white.opacity(0.14)
    static let surface = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.40)

    /// Pozadí karty na Lock Screenu – tmavé jako Island, ať obě prezentace působí jako jeden celek.
    static let lockBackground = Color(red: 0.05, green: 0.05, blue: 0.06)
}

// MARK: - Animace

extension Animation {
    /// Pružná animace pro výplně a prstence. Celé trvání pod limitem 2 s.
    static let island = Animation.spring(duration: 0.9, bounce: 0.28)
    static let islandSoft = Animation.smooth(duration: 0.6)
}

private struct IslandAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    var animation: Animation
    var value: V

    func body(content: Content) -> some View {
        content.animation(isLuminanceReduced ? nil : animation, value: value)
    }
}

extension View {
    /// Animace, která se vypne na Always-On displeji (doporučení Apple).
    func islandAnimation<V: Equatable>(_ animation: Animation = .island, value: V) -> some View {
        modifier(IslandAnimationModifier(animation: animation, value: value))
    }
}

// MARK: - Formátování

enum IslandFormat {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    static func amount(_ value: Double) -> String {
        grouped.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// Krátký zápis pro compact presentation: 56 600 → „57k“, 1 250 000 → „1,3M“.
    static func short(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            let m = value / 1_000_000
            return (m >= 10 ? String(format: "%.0f", m) : String(format: "%.1f", m))
                .replacingOccurrences(of: ".", with: ",") + "M"
        }
        if absValue >= 1_000 {
            return String(format: "%.0f", value / 1_000) + "k"
        }
        return String(format: "%.0f", value)
    }

    static func percent(_ progress: Double) -> Int {
        Int((min(max(progress, 0), 9.99) * 100).rounded())
    }

    static func czechCount(_ n: Int, one: String, few: String, many: String) -> String {
        let mod10 = abs(n) % 10
        let mod100 = abs(n) % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}

// MARK: - Prstenec (inspirováno „activity rings“)

struct IslandRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 4

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(IslandPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(clamped, 0.05))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(clamped > 0 ? 1 : 0)
        }
        .islandAnimation(value: clamped)
    }
}

/// Malý prstenec do compact/minimal – vejde se do 28 pt kruhu.
struct IslandMiniRing<Center: View>: View {
    var progress: Double
    var tint: Color
    var size: CGFloat = 22
    var lineWidth: CGFloat = 3.2
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            IslandRing(progress: progress, tint: tint, lineWidth: lineWidth)
            center()
        }
        .frame(width: size, height: size)
    }
}

extension IslandMiniRing where Center == EmptyView {
    init(progress: Double, tint: Color, size: CGFloat = 22, lineWidth: CGFloat = 3.2) {
        self.init(progress: progress, tint: tint, size: size, lineWidth: lineWidth) { EmptyView() }
    }
}

// MARK: - Sloupcový ukazatel (inspirováno UV grafem)

/// Řada sloupků, které se zleva plní barevným přechodem. Každý sloupek
/// má malé zpoždění, takže výplň „přeteče“ zleva doprava (celkem < 2 s).
struct IslandBarMeter: View {
    var progress: Double
    var colors: [Color]
    var segments: Int = 28
    var height: CGFloat = 24
    /// Pozice značek (0…1), např. polovina cíle.
    var markers: [Double] = []

    private var clamped: Double { min(max(progress, 0), 1) }
    private var filled: Int { Int((clamped * Double(segments)).rounded()) }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(segments - 1)) / CGFloat(segments))
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<segments, id: \.self) { index in
                        let isOn = index < filled
                        Capsule(style: .continuous)
                            .fill(isOn ? color(at: index) : IslandPalette.surface)
                            .frame(width: barWidth, height: isOn ? height : height * 0.72)
                            .islandAnimation(.island.delay(Double(index) * 0.018), value: isOn)
                    }
                }
                .frame(height: height, alignment: .bottom)

                ForEach(markers, id: \.self) { marker in
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(IslandPalette.tertiary)
                        .offset(x: CGFloat(marker) * geo.size.width - 3, y: -8)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        guard colors.count > 1 else { return colors.first ?? .white }
        let t = Double(index) / Double(max(segments - 1, 1))
        let scaled = t * Double(colors.count - 1)
        let lower = Int(scaled.rounded(.down))
        return colors[min(lower + (scaled - Double(lower) > 0.5 ? 1 : 0), colors.count - 1)]
    }
}

// MARK: - Dlaždice s prstencem (manažer, národní manažer)

struct IslandGaugeTile: View {
    enum Style {
        /// Prstenec s postupem.
        case ring(Double)
        /// Plný kruh – vhodné pro počet bez cíle (např. služby dnes).
        case badge
        /// Zvýraznění upozornění – prstenec plný, když je hodnota > 0.
        case alert(Bool)
    }

    var symbol: String
    var value: String
    var numericValue: Double
    var caption: String
    var tint: Color
    var style: Style
    var ringSize: CGFloat = 40
    /// Vodorovné rozložení (prstenec vlevo, hodnota vpravo) – nízké, pro Lock Screen.
    var horizontal = false

    var body: some View {
        if horizontal {
            HStack(spacing: 7) {
                gauge
                VStack(alignment: .leading, spacing: 0) {
                    valueText
                    captionText
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(caption) \(value)")
        } else {
            VStack(spacing: 5) {
                gauge
                valueText
                captionText
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(caption) \(value)")
        }
    }

    private var gauge: some View {
            ZStack {
                switch style {
                case .ring(let progress):
                    IslandRing(progress: progress, tint: tint, lineWidth: 4.5)
                case .badge:
                    Circle()
                        .fill(tint.gradient)
                case .alert(let active):
                    IslandRing(progress: active ? 1 : 0, tint: tint, lineWidth: 4.5)
                }
                Image(systemName: symbol)
                    .font(.system(size: ringSize * 0.36, weight: .bold))
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: ringSize, height: ringSize)
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(valueColor)
            .contentTransition(.numericText(value: numericValue))
            .islandAnimation(.islandSoft, value: numericValue)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var captionText: some View {
        Text(caption.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(IslandPalette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var iconColor: Color {
        switch style {
        case .badge: return IslandPalette.ink
        default: return tint
        }
    }

    private var valueColor: Color {
        switch style {
        case .alert(let active): return active ? tint : .white
        default: return tint
        }
    }
}

// MARK: - Malé prvky

/// Značka aplikace v rozbaleném Islandu – bez kontejneru ikony (HIG: nepoužívat celou ikonu aplikace).
struct IslandBrandHeader: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandPalette.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 4)
    }
}

/// Kapsle s ikonou a textem (stav, další instalace, poslední problém).
struct IslandChip: View {
    var symbol: String
    var text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.16), in: Capsule(style: .continuous))
    }
}

/// Text s pevnou šířkou skrytého vzoru. Bez ní se compact Island roztahuje
/// podle obsahu a při každé změně čísla „poskakuje“.
struct IslandFixedWidthText: View {
    var text: String
    var probe: String
    var numericValue: Double
    var alignment: Alignment = .trailing

    var body: some View {
        Text(probe)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: alignment) {
                Text(text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: numericValue))
                    .islandAnimation(.islandSoft, value: numericValue)
            }
            .lineLimit(1)
    }
}

/// Velké číslo s plynulou změnou číslic.
struct IslandNumber: View {
    var text: String
    var value: Double
    var size: CGFloat
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: value))
            .islandAnimation(.islandSoft, value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Sloupcový graf po dnech (výkon)

/// Graf hodnot po dnech. Sloupky „vyrostou“ postupně zleva, dnešek je zvýrazněný.
struct IslandColumnChart: View {
    var values: [Int]
    var labels: [String]
    var colors: [Color] = [IslandPalette.amber, IslandPalette.yellow]
    var height: CGFloat = 60
    var showsValues = true

    private var maxValue: Int { max(values.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isToday = index == values.count - 1
                let ratio = CGFloat(value) / CGFloat(maxValue)
                VStack(spacing: 3) {
                    if showsValues {
                        Text("\(value)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? IslandPalette.yellow : IslandPalette.tertiary)
                            .contentTransition(.numericText(value: Double(value)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    ZStack(alignment: .bottom) {
                        Capsule(style: .continuous)
                            .fill(IslandPalette.surface)
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isToday ? colors : colors.map { $0.opacity(0.55) },
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: max(4, height * ratio))
                            .islandAnimation(.island.delay(Double(index) * 0.06), value: value)
                    }
                    .frame(maxWidth: 14)
                    .frame(height: height)
                    if index < labels.count {
                        Text(labels[index])
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isToday ? .white : IslandPalette.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Služby po dnech: " + values.map(String.init).joined(separator: ", "))
    }
}

/// Miniaturní graf do compact presentation (šířka ~ 22 pt).
struct IslandSparkBars: View {
    var values: [Int]
    var tint: Color = IslandPalette.yellow
    var height: CGFloat = 14

    var body: some View {
        let shown = Array(values.suffix(5))
        let maxValue = max(shown.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, value in
                Capsule(style: .continuous)
                    .fill(index == shown.count - 1 ? tint : tint.opacity(0.5))
                    .frame(width: 3, height: max(3, height * CGFloat(value) / CGFloat(maxValue)))
                    .islandAnimation(.island.delay(Double(index) * 0.05), value: value)
            }
            if shown.isEmpty {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Řádek „hodnota + popisek“ pro detailní výpis v rozbaleném Islandu.
struct IslandStatRow: View {
    var symbol: String
    var title: String
    var value: String
    var numericValue: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandPalette.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: numericValue))
                .islandAnimation(.islandSoft, value: numericValue)
        }
    }
}

// MARK: - Hlavní číslo vpravo nahoře

/// Hlavní číslo s popiskem. `inline` = na jednom řádku (nízké, pro Lock Screen).
struct IslandHeadlineValue: View {
    var text: String
    var value: Double
    var caption: String
    var color: Color
    var inline = false

    var body: some View {
        if inline {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                IslandNumber(text: text, value: value, size: 22, color: color)
                captionView(size: 12)
            }
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                IslandNumber(text: text, value: value, size: 26, color: color)
                captionView(size: 11)
            }
        }
    }

    private func captionView(size: CGFloat) -> some View {
        Text(caption)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(IslandPalette.secondary)
            .lineLimit(1)
    }
}

extension View {
    /// Okraje karty na Lock Screenu (HIG: standardní okraj 14 pt) – ve widgetu i v náhledu stejné.
    func islandLockCardPadding() -> some View {
        padding(.horizontal, 16).padding(.vertical, 14)
    }
}
