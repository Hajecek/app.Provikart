//
//  QualificationView.swift
//  Provikart
//

import SwiftUI

struct QualificationView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var progress: QualificationProgress?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private let service = QualificationService()

    var body: some View {
        ScrollView {
            if let progress {
                VStack(alignment: .leading, spacing: 16) {
                    QualificationLevelCard(progress: progress)
                    if !progress.startedLabel.isEmpty {
                        Text("Od \(progress.startedLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !progress.localityGaps.isEmpty {
                        localityCard(progress)
                    }
                    if progress.modelaceMet || !progress.modelaceNote.isEmpty {
                        modelaceCard(progress)
                    }
                    if !progress.message.isEmpty {
                        Text(progress.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 14) {
                        ForEach(progress.bars) { bar in
                            barRow(bar)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Kvalifikace")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading && progress == nil {
                ProgressView()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func localityCard(_ progress: QualificationProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nevyplněné lokality")
                .font(.caption.weight(.bold))
                .foregroundStyle(LocalityCardColors.title)
            ForEach(Array(progress.localityGaps.enumerated()), id: \.offset) { _, gap in
                let lines = splitLocalityAddress(gap.address)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lines.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LocalityCardColors.address)
                        .fixedSize(horizontal: false, vertical: true)
                    if !lines.place.isEmpty {
                        Text(lines.place)
                            .font(.caption)
                            .foregroundStyle(LocalityCardColors.place)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(LocalityCardColors.row, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            let hidden = progress.localityUnfilled - progress.localityGaps.count
            if hidden > 0 {
                Text("A dalších \(hidden).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LocalityCardColors.title)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LocalityCardColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// „Lom, 142, Studánka, Pardubice, Pardubice“ → ulice a zbytek bez opakovaného okresu.
    private func splitLocalityAddress(_ address: String) -> (title: String, place: String) {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return (address, "") }
        let number = parts[1].range(of: #"^\d"#, options: .regularExpression) != nil
        let title = number ? "\(parts[0]) \(parts[1])" : parts[0]
        var rest = Array(parts.dropFirst(number ? 2 : 1))
        while rest.count >= 2, rest[rest.count - 1].caseInsensitiveCompare(rest[rest.count - 2]) == .orderedSame {
            rest.removeLast()
        }
        return (title, rest.joined(separator: ", "))
    }

    private func modelaceCard(_ progress: QualificationProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Modelace")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progress.modelaceMet ? "Splněno" : "Zatím ne")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(progress.modelaceMet ? Color.green : Color.secondary)
            }
            if !progress.modelaceNote.isEmpty {
                Text(progress.modelaceNote)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func barRow(_ bar: QualificationBar) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(qualificationBarColor(bar.key))
                    .frame(width: 8, height: 8)
                Text(bar.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(bar.key == "modelace" || bar.key == "localities" ? (bar.met ? "Splněno" : "Čeká") : "\(bar.current) / \(bar.target)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(bar.met ? Color.green : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(qualificationBarColor(bar.key))
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, bar.percent))) / 100)
                }
            }
            .frame(height: 8)
            if !bar.hint.isEmpty {
                Text(bar.hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func load() async {
        let token = await MainActor.run { authState.authToken }
        do {
            let next = try await service.fetchProgress(token: token)
            await MainActor.run {
                progress = next
                errorMessage = nil
                isLoading = false
            }
        } catch {
            await MainActor.run {
                if progress == nil {
                    errorMessage = "Kvalifikaci se nepodařilo načíst."
                }
                isLoading = false
            }
        }
    }
}

struct QualificationLevelCard: View {
    let progress: QualificationProgress
    var showsChevron: Bool = false

    var body: some View {
        QualificationLevelRow(progress: progress, showsChevron: showsChevron)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(QualificationLevelBackdrop())
    }
}

struct QualificationLevelRow: View {
    let progress: QualificationProgress
    var showsChevron: Bool = true

    private var fraction: CGFloat {
        CGFloat(min(100, max(0, progress.percent))) / 100
    }

    private var accent: Color { Color(red: 0.62, green: 0.86, blue: 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kvalifikace")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(progress.qualified ? "Splněno" : "K dokončení")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(min(100, max(0, progress.percent))) %")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent, Color.white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kvalifikace \(progress.percent) procent")
    }
}

struct QualificationLevelBackdrop: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let glow = Color(red: 0.45, green: 0.78, blue: 1.0)
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.18, blue: 0.38),
                            Color(red: 0.04, green: 0.45, blue: 0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            shape
                .fill(
                    RadialGradient(
                        colors: [glow.opacity(0.28), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
            shape
                .stroke(glow.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.04, green: 0.35, blue: 0.7).opacity(0.22), radius: 6, y: 2)
    }
}

private enum LocalityCardColors {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let card = adaptive(
        light: UIColor(red: 1, green: 0.945, blue: 0.949, alpha: 1),
        dark: UIColor(red: 0.24, green: 0.10, blue: 0.12, alpha: 1)
    )
    static let row = adaptive(
        light: .white,
        dark: UIColor(red: 0.14, green: 0.07, blue: 0.08, alpha: 1)
    )
    static let title = adaptive(
        light: UIColor(red: 0.55, green: 0.11, blue: 0.16, alpha: 1),
        dark: UIColor(red: 1, green: 0.76, blue: 0.79, alpha: 1)
    )
    static let address = adaptive(
        light: UIColor(red: 0.18, green: 0.07, blue: 0.09, alpha: 1),
        dark: UIColor(red: 1, green: 0.94, blue: 0.95, alpha: 1)
    )
    static let place = adaptive(
        light: UIColor(red: 0.45, green: 0.24, blue: 0.27, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.72, blue: 0.75, alpha: 1)
    )
}

struct QualificationChipFlow: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: QualificationProgress

    var body: some View {
        QualificationFlow(spacing: 6) {
            ForEach(progress.bars) { bar in
                chip(bar)
            }
        }
    }

    private func chip(_ bar: QualificationBar) -> some View {
        let tone = chipTone(bar)
        return HStack(spacing: 6) {
            Circle()
                .fill(tone.dot)
                .frame(width: 6, height: 6)
            Text(tone.text)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.background, in: Capsule())
        .overlay(Capsule().stroke(tone.border, lineWidth: 1))
    }

    private func chipTone(_ bar: QualificationBar) -> (text: String, dot: Color, foreground: Color, background: Color, border: Color) {
        if bar.key == "localities" && !bar.met {
            let dark = colorScheme == .dark
            return (
                "Lokality · čeká",
                Color(red: 0.86, green: 0.25, blue: 0.33),
                dark ? Color(red: 1, green: 0.78, blue: 0.80) : Color(red: 0.55, green: 0.11, blue: 0.18),
                dark ? Color(red: 0.28, green: 0.10, blue: 0.12) : Color(red: 1, green: 0.95, blue: 0.95),
                dark ? Color(red: 0.55, green: 0.22, blue: 0.26) : Color(red: 0.98, green: 0.78, blue: 0.80)
            )
        }
        if bar.key == "localities" && bar.met {
            return ("Lokality · splněno", Color.green, Color(red: 0.08, green: 0.40, blue: 0.20), Color.green.opacity(0.12), Color.green.opacity(0.28))
        }
        if bar.key == "modelace" {
            if bar.met {
                return ("Modelace · splněno", Color.green, Color(red: 0.08, green: 0.40, blue: 0.20), Color.green.opacity(0.12), Color.green.opacity(0.28))
            }
            return ("Modelace · čeká", qualificationBarColor(bar.key), .secondary, Color(.secondarySystemGroupedBackground), Color(.separator))
        }
        if bar.met {
            return ("\(bar.label) \(bar.current)/\(bar.target)", qualificationBarColor(bar.key), Color(red: 0.08, green: 0.40, blue: 0.20), Color.green.opacity(0.12), Color.green.opacity(0.28))
        }
        return ("\(bar.label) \(bar.current)/\(bar.target)", qualificationBarColor(bar.key), .primary, Color(.secondarySystemGroupedBackground), Color(.separator))
    }
}

func qualificationBarColor(_ key: String) -> Color {
    switch key {
    case "internet": return Color(red: 0.043, green: 0.518, blue: 0.890)
    case "postpaid": return Color(red: 0.345, green: 0.337, blue: 0.839)
    case "oneplay": return Color(red: 1, green: 0.584, blue: 0)
    case "family": return Color(red: 0.686, green: 0.322, blue: 0.871)
    case "transfer": return Color(red: 0.557, green: 0.557, blue: 0.576)
    case "performance": return Color(red: 0.204, green: 0.780, blue: 0.349)
    case "localities": return Color(red: 1, green: 0.420, blue: 0.290)
    case "modelace": return Color(red: 0.188, green: 0.690, blue: 0.780)
    default: return Color(red: 0.043, green: 0.518, blue: 0.890)
    }
}

struct QualificationFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
