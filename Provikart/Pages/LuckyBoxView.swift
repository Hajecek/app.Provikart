//
//  LuckyBoxView.swift
//  Provikart
//
//  Denní Lucky Box – hvězdy (UX), otevření přes collectibles_chest.php.
//

import SwiftUI
import Photos
import UIKit

// MARK: - Model

enum LuckyBoxRarity: String, Codable, CaseIterable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var title: String {
        switch self {
        case .common: return "Běžná"
        case .uncommon: return "Neobvyklá"
        case .rare: return "Vzácná"
        case .epic: return "Epická"
        case .legendary: return "Legendární"
        }
    }

    var stars: Int {
        switch self {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 3
        case .epic: return 4
        case .legendary: return 5
        }
    }

    static func from(stars: Int) -> LuckyBoxRarity {
        switch stars {
        case 1: return .common
        case 2: return .uncommon
        case 3: return .rare
        case 4: return .epic
        case 5: return .legendary
        default: return .common
        }
    }

    static func from(api raw: String?) -> LuckyBoxRarity {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "1", "common", "bezna", "běžná", "bezny", "běžný", "common_1":
            return .common
        case "2", "uncommon", "neobvykla", "neobvyklá", "neobvykly", "neobvyklý":
            return .uncommon
        case "3", "rare", "vzacna", "vzácná", "vzacny", "vzácný":
            return .rare
        case "4", "epic", "epicka", "epická", "epicky", "epický":
            return .epic
        case "5", "legendary", "legendarni", "legendární", "mythic", "myticka", "mytická":
            return .legendary
        default:
            return .common
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self.from(api: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var tint: Color {
        switch self {
        case .common: return Color(red: 0.55, green: 0.78, blue: 1.0)
        case .uncommon: return Color(red: 0.45, green: 0.85, blue: 0.75)
        case .rare: return Color(red: 0.72, green: 0.55, blue: 1.0)
        case .epic: return Color(red: 1.0, green: 0.82, blue: 0.28)
        case .legendary: return Color(red: 1.0, green: 0.35, blue: 0.42)
        }
    }

    /// Druhá barva partiklů / jisker.
    var particleSecondary: Color {
        switch self {
        case .common: return Color(red: 0.75, green: 0.9, blue: 1.0)
        case .uncommon: return Color(red: 0.55, green: 1.0, blue: 0.82)
        case .rare: return Color(red: 0.95, green: 0.7, blue: 1.0)
        case .epic: return Color(red: 1.0, green: 0.55, blue: 0.2)
        case .legendary: return Color(red: 1.0, green: 0.75, blue: 0.35)
        }
    }

    var atmosphereParticleCount: Int {
        switch self {
        case .common: return 22
        case .uncommon: return 28
        case .rare: return 34
        case .epic: return 40
        case .legendary: return 48
        }
    }

    var atmosphereSpeed: Double {
        switch self {
        case .common: return 0.85
        case .uncommon: return 1.0
        case .rare: return 1.15
        case .epic: return 1.35
        case .legendary: return 1.55
        }
    }

    var glowStrength: Double {
        switch self {
        case .common: return 0.22
        case .uncommon: return 0.28
        case .rare: return 0.34
        case .epic: return 0.42
        case .legendary: return 0.52
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .common:
            return [
                Color(red: 0.12, green: 0.32, blue: 0.78),
                Color(red: 0.05, green: 0.14, blue: 0.42),
                Color(red: 0.02, green: 0.05, blue: 0.16)
            ]
        case .uncommon:
            return [
                Color(red: 0.06, green: 0.52, blue: 0.55),
                Color(red: 0.03, green: 0.28, blue: 0.38),
                Color(red: 0.02, green: 0.08, blue: 0.18)
            ]
        case .rare:
            return [
                Color(red: 0.48, green: 0.16, blue: 0.82),
                Color(red: 0.26, green: 0.06, blue: 0.48),
                Color(red: 0.08, green: 0.02, blue: 0.18)
            ]
        case .epic:
            return [
                Color(red: 0.78, green: 0.42, blue: 0.06),
                Color(red: 0.52, green: 0.14, blue: 0.22),
                Color(red: 0.14, green: 0.04, blue: 0.14)
            ]
        case .legendary:
            return [
                Color(red: 0.62, green: 0.08, blue: 0.14),
                Color(red: 0.32, green: 0.04, blue: 0.18),
                Color(red: 0.08, green: 0.01, blue: 0.05)
            ]
        }
    }

    var defaultIcon: String {
        switch self {
        case .common: return "cube.fill"
        case .uncommon: return "sparkles"
        case .rare: return "diamond.fill"
        case .epic: return "crown.fill"
        case .legendary: return "flame.fill"
        }
    }
}

struct LuckyBoxReward: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let rarity: LuckyBoxRarity
    let weight: Int
    var collectibleId: Int?
    var imageURL: String?
    var duplicate: Bool
    var powderGained: Int
    var qty: Int
    var balance: Int?
    var currencyNameOf: String?
    var message: String?
    var isOwned: Bool
    var showsChestOutcome: Bool
    var powderNeed: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, iconName, rarity, weight
        case collectibleId, imageURL, duplicate, powderGained, qty, balance
        case currencyNameOf, message, isOwned, showsChestOutcome, powderNeed
    }

    init(
        id: String,
        title: String,
        subtitle: String,
        iconName: String,
        rarity: LuckyBoxRarity,
        weight: Int,
        collectibleId: Int? = nil,
        imageURL: String? = nil,
        duplicate: Bool = false,
        powderGained: Int = 0,
        qty: Int = 1,
        balance: Int? = nil,
        currencyNameOf: String? = nil,
        message: String? = nil,
        isOwned: Bool = true,
        showsChestOutcome: Bool = false,
        powderNeed: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.rarity = rarity
        self.weight = weight
        self.collectibleId = collectibleId
        self.imageURL = imageURL
        self.duplicate = duplicate
        self.powderGained = powderGained
        self.qty = qty
        self.balance = balance
        self.currencyNameOf = currencyNameOf
        self.message = message
        self.isOwned = isOwned
        self.showsChestOutcome = showsChestOutcome
        self.powderNeed = powderNeed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        iconName = try c.decode(String.self, forKey: .iconName)
        rarity = try c.decode(LuckyBoxRarity.self, forKey: .rarity)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        collectibleId = try c.decodeIfPresent(Int.self, forKey: .collectibleId)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        duplicate = try c.decodeIfPresent(Bool.self, forKey: .duplicate) ?? false
        powderGained = try c.decodeIfPresent(Int.self, forKey: .powderGained) ?? 0
        qty = try c.decodeIfPresent(Int.self, forKey: .qty) ?? 1
        balance = try c.decodeIfPresent(Int.self, forKey: .balance)
        currencyNameOf = try c.decodeIfPresent(String.self, forKey: .currencyNameOf)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        isOwned = try c.decodeIfPresent(Bool.self, forKey: .isOwned) ?? true
        showsChestOutcome = try c.decodeIfPresent(Bool.self, forKey: .showsChestOutcome) ?? false
        powderNeed = try c.decodeIfPresent(Int.self, forKey: .powderNeed)
    }

    init(from result: CollectiblesChestOpenResult, rarity overrideRarity: LuckyBoxRarity? = nil) {
        let item = result.item
        let rarity = overrideRarity ?? LuckyBoxRarity.from(api: item.rarity)
        self.id = "collectible-\(item.id)"
        self.title = item.name
        if result.duplicate {
            self.subtitle = item.description?.isEmpty == false
                ? (item.description ?? "")
                : "Už máš ve sbírce"
        } else if let description = item.description, !description.isEmpty {
            self.subtitle = description
        } else {
            self.subtitle = "Nový předmět ve sbírce"
        }
        self.iconName = rarity.defaultIcon
        self.rarity = rarity
        self.weight = 1
        self.collectibleId = item.id
        self.imageURL = item.resolvedImageURL?.absoluteString ?? item.imageURL
        self.duplicate = result.duplicate
        self.powderGained = result.powderGained
        self.qty = result.qty
        self.balance = result.balance
        self.currencyNameOf = result.currency.nameOf
        self.message = result.message
        self.isOwned = true
        self.showsChestOutcome = true
        self.powderNeed = item.need
    }

    init(from item: CollectibleItem, currency: CollectiblesCurrency = CollectiblesCurrency()) {
        let rarity = LuckyBoxRarity.from(api: item.rarity)
        self.id = "collectible-\(item.id)"
        self.title = item.name
        self.subtitle = item.description ?? ""
        self.iconName = rarity.defaultIcon
        self.rarity = rarity
        self.weight = 1
        self.collectibleId = item.id
        self.imageURL = item.resolvedImageURL?.absoluteString ?? item.imageURL
        self.duplicate = false
        self.powderGained = 0
        self.qty = max(item.qty, item.owned ? 1 : 0)
        self.balance = nil
        self.currencyNameOf = currency.nameOf
        self.message = nil
        self.isOwned = item.owned
        self.showsChestOutcome = false
        self.powderNeed = item.need
    }

    var resolvedImageURL: URL? {
        guard let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://provikart.cz/\(trimmed)")
    }
}

enum LuckyBoxPhase: Equatable {
    /// 4 pokusy o upgrade hvězd
    case charging
    /// Pokusy vyčerpány – klepnutím otevřít
    case readyToOpen
    case opening
    case revealed
}

// MARK: - Local store

enum LuckyBoxLocalStore {
    private static let dayKey = "lucky_box_last_open_day"
    private static let rewardKey = "lucky_box_last_reward"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func todayKey(reference: Date = Date()) -> String {
        dayFormatter.string(from: reference)
    }

    static var hasOpenedToday: Bool {
        UserDefaults.standard.string(forKey: dayKey) == todayKey()
    }

    /// Auto-ukázat při startu appky, dokud dnešní bedna není otevřená.
    static var shouldAutoPresent: Bool {
        !hasOpenedToday
    }

    static var lastReward: LuckyBoxReward? {
        guard let data = UserDefaults.standard.data(forKey: rewardKey) else { return nil }
        return try? JSONDecoder().decode(LuckyBoxReward.self, from: data)
    }

    static func saveOpen(reward: LuckyBoxReward, on date: Date = Date()) {
        UserDefaults.standard.set(todayKey(reference: date), forKey: dayKey)
        if let data = try? JSONEncoder().encode(reward) {
            UserDefaults.standard.set(data, forKey: rewardKey)
        }
    }

    static func resetToday() {
        UserDefaults.standard.removeObject(forKey: dayKey)
        UserDefaults.standard.removeObject(forKey: rewardKey)
    }

    static func secondsUntilNextOpen(reference: Date = Date()) -> TimeInterval {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startOfTomorrow = calendar.startOfDay(for: reference)
            .addingTimeInterval(24 * 60 * 60)
        return max(0, startOfTomorrow.timeIntervalSince(reference))
    }

    static func countdownText(reference: Date = Date()) -> String {
        let total = Int(secondsUntilNextOpen(reference: reference))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

enum LuckyBoxMockPool {
    static let maxClicks = 4
    /// Max hvězd = legendary (1…5).
    static let maxStars = 5

    /// Šance na +1 hvězdu (raritu) při klepnutí.
    static func upgradeChance(fromStars: Int) -> Double {
        switch fromStars {
        case 1: return 0.42 // → uncommon
        case 2: return 0.28 // → rare
        case 3: return 0.16 // → epic
        case 4: return 0.08 // → legendary
        default: return 0
        }
    }
}

// MARK: - View

struct LuckyBoxView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var phase: LuckyBoxPhase
    @State private var stars: Int
    @State private var clicksLeft: Int
    @State private var reward: LuckyBoxReward?
    @State private var hasOpenedToday: Bool
    @State private var boxScale: CGFloat = 1
    @State private var boxRotation: Double = 0
    @State private var boxBounce: CGFloat = 0
    /// 0…1 – expandující aura kolem bedny při klepnutí.
    @State private var hitAuraProgress: CGFloat = 0
    /// true = silnější aura (upgrade hvězdy).
    @State private var hitAuraIntense = false
    @State private var lidOpen: CGFloat
    @State private var glowPulse = false
    @State private var revealOpacity: Double
    @State private var flashOpacity: Double = 0
    @State private var starBurst = false
    @State private var particleBoost = false
    @State private var isBusy = false
    /// Zámek mezi klepnutími – dokud se bedna otáčí / třese.
    @State private var isClickLocked = false
    @State private var countdownTick = Date()
    @State private var hitAnimationTask: Task<Void, Never>?
    @State private var shakeParticles: [LuckyShakeParticle] = []
    @State private var rewardCardScale: CGFloat
    @State private var rewardCardOpacity: Double
    @State private var rewardCardImage: UIImage?
    @State private var shareReward: LuckyBoxReward?
    @State private var infoReward: LuckyBoxReward?
    @State private var openErrorMessage: String?
    @State private var showOpenError = false
    @State private var openTask: Task<Void, Never>?
    /// Pořadové číslo otevření – staré (zrušené) tasky nesmí měnit stav.
    @State private var openGeneration = 0

    private let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
    private let orange = Color(red: 0.97, green: 0.58, blue: 0.12)

    init() {
        let opened = LuckyBoxLocalStore.hasOpenedToday
        let last = LuckyBoxLocalStore.lastReward
        _hasOpenedToday = State(initialValue: opened)

        if opened, let last {
            _phase = State(initialValue: .revealed)
            _reward = State(initialValue: last)
            _stars = State(initialValue: last.rarity.stars)
            _clicksLeft = State(initialValue: 0)
            _revealOpacity = State(initialValue: 1)
            _lidOpen = State(initialValue: 1)
            _rewardCardOpacity = State(initialValue: 1)
            _rewardCardScale = State(initialValue: 1)
            if let url = last.resolvedImageURL {
                _rewardCardImage = State(initialValue: CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: 1200))
            } else {
                _rewardCardImage = State(initialValue: nil)
            }
        } else {
            _phase = State(initialValue: .charging)
            _reward = State(initialValue: nil)
            _stars = State(initialValue: 1)
            _clicksLeft = State(initialValue: LuckyBoxMockPool.maxClicks)
            _revealOpacity = State(initialValue: 0)
            _lidOpen = State(initialValue: 0)
            _rewardCardOpacity = State(initialValue: 0)
            _rewardCardScale = State(initialValue: 0.72)
            _rewardCardImage = State(initialValue: nil)
        }
    }

    private var currentRarity: LuckyBoxRarity {
        // Během nabíjení řídí atmosféru hvězdy; po reveal karty rarity z odměny
        if phase == .revealed, let reward {
            return reward.rarity
        }
        return LuckyBoxRarity.from(stars: stars)
    }

    var body: some View {
        ZStack {
            fullscreenBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.85), value: currentRarity)

            particlesLayer
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.7), value: currentRarity)

            VStack(spacing: 0) {
                if phase != .revealed {
                    starsRow
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 8)

                chestView
                    .padding(.horizontal, phase == .revealed ? 8 : 24)

                Spacer(minLength: 16)

                // Rezerva výšky – samotný hint je v overlay, ať neskáče se Spacerem.
                Color.clear
                    .frame(height: phase == .revealed || (hasOpenedToday && phase != .opening) ? 120 : 100)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.35), value: phase)
            .overlay(alignment: .bottom) {
                bottomSection
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                    // Odřízni implicitní animace z otáčení bedny / hvězd.
                    .transaction { $0.animation = nil }
            }

            // flash musí být navrchu – zakryje bednu i UI
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleScreenTap()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if phase == .revealed {
                    toolbarCountdown
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if phase == .revealed, let reward {
                    Button("Info", systemImage: "info.circle") {
                        infoReward = reward
                    }
                    .accessibilityLabel("Detail karty")

                    Button("Sdílet", systemImage: "square.and.arrow.up") {
                        shareReward = reward
                    }
                    .accessibilityLabel("Sdílet kartu kamarádům")
                }

                Button("Reset", systemImage: "arrow.counterclockwise") {
                    resetForTesting()
                }
                .accessibilityLabel("Resetovat dnešní Lucky Box")
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $shareReward) { reward in
            LuckyShareStudioView(reward: reward, gold: gold, preloadedImage: rewardCardImage)
        }
        .sheet(item: $infoReward) { reward in
            LuckyCardInfoSheet(reward: reward, gold: gold, orange: orange, preloadedImage: rewardCardImage)
        }
        .alert("Bednu se nepodařilo otevřít", isPresented: $showOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openErrorMessage ?? "Zkus to znovu.")
        }
        .onAppear {
            glowPulse = true
            // Záloha, kdyby se store změnil mimo init (např. reset jinde).
            restoreRevealedStateIfNeeded()
        }
        .task(id: reward?.id) {
            await ensureRewardCardImageLoaded()
        }
        .task(id: phase == .revealed) {
            while !Task.isCancelled {
                countdownTick = Date()
                let interval: UInt64 = phase == .revealed ? 1_000_000_000 : 30_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private var toolbarCountdown: some View {
        VStack(spacing: 1) {
            Text("DALŠÍ ZA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(LuckyBoxLocalStore.countdownText(reference: countdownTick))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Další bedna za \(LuckyBoxLocalStore.countdownText(reference: countdownTick))")
    }

    private var fullscreenBackground: some View {
        let rarity = currentRarity
        let colors = rarity.backgroundColors
        let tint = rarity.tint
        let glow = rarity.glowStrength
        let burstBoost = starBurst ? 0.22 : 0
        return ZStack {
            LinearGradient(
                colors: [colors[0], colors[1], colors[2], .black],
                startPoint: .top,
                endPoint: .bottom
            )

            // horní aura rarity
            RadialGradient(
                colors: [
                    Color.white.opacity(0.14 + glow * 0.25),
                    tint.opacity(0.2 + glow * 0.35 + burstBoost),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 8,
                endRadius: 340
            )

            // středový glow kolem bedny
            RadialGradient(
                colors: [
                    tint.opacity((glowPulse ? glow + 0.12 : glow * 0.65) + burstBoost),
                    tint.opacity(glow * 0.25),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 16,
                endRadius: 260
            )
            .animation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true), value: glowPulse)
            .animation(.easeOut(duration: 0.45), value: starBurst)

            // sekundární jiskra (legendary/epic výraznější)
            RadialGradient(
                colors: [
                    rarity.particleSecondary.opacity(glow * 0.35 + burstBoost * 0.5),
                    .clear
                ],
                center: UnitPoint(x: 0.22, y: 0.28),
                startRadius: 4,
                endRadius: 180
            )
            .blendMode(.plusLighter)

            RadialGradient(
                colors: [
                    tint.opacity(glow * 0.28 + burstBoost * 0.4),
                    .clear
                ],
                center: UnitPoint(x: 0.82, y: 0.22),
                startRadius: 4,
                endRadius: 160
            )
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.28), Color.black.opacity(0.72)],
                startPoint: UnitPoint(x: 0.5, y: 0.52),
                endPoint: .bottom
            )

            LuckySoftFloor(accent: tint, intensity: glow)
                .opacity(0.45 + glow * 0.45)
                .allowsHitTesting(false)

            // viněta
            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.45 + glow * 0.2)],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 120,
                endRadius: 540
            )
        }
    }

    private var particlesLayer: some View {
        let rarity = currentRarity
        let tint = rarity.tint
        let secondary = rarity.particleSecondary
        let speedMul = rarity.atmosphereSpeed
        let baseCount = rarity.atmosphereParticleCount
        let count = particleBoost ? baseCount + 18 : baseCount
        let revealedDim = phase == .revealed ? 0.35 : 1.0

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate * speedMul
                for i in 0..<count {
                    let seed = Double(i) * 17.13 + 3.7
                    let dirX = sin(seed * 1.9)
                    let dirY = cos(seed * 2.3)
                    let speed = (0.2 + Double(i % 7) * 0.055) * speedMul
                    let drift = 16 + Double(i % 5) * 7 + Double(rarity.stars) * 2.5
                    let baseX = (sin(seed) * 0.5 + 0.5) * size.width
                    let baseY = (cos(seed * 1.4) * 0.5 + 0.5) * size.height * 0.88
                    let x = baseX + dirX * sin(t * speed + seed) * drift
                    let y = baseY + dirY * cos(t * speed * 0.9 + seed * 1.1) * (12 + Double(i % 4) * 5)
                        - (t * (7 + Double(i % 6) * 3.2) + seed * 20)
                            .truncatingRemainder(dividingBy: Double(size.height * 0.58))
                    let r = 1.1 + CGFloat(i % 5) * 0.75 + CGFloat(rarity.stars) * 0.12
                    let kind = i % 4
                    let color: Color = {
                        switch kind {
                        case 0: return tint
                        case 1: return secondary
                        case 2: return .white
                        default: return tint.opacity(0.85)
                        }
                    }()
                    let alpha = (0.14 + 0.3 * Double((i % 4) + 1) / 4.0) * revealedDim
                        * (0.75 + rarity.glowStrength)

                    var path = Path()
                    path.addEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                    context.fill(path, with: .color(color.opacity(alpha)))

                    // větší „jiskry“ u vyšších rarit
                    if rarity.stars >= 3, i % 5 == 0 {
                        var spark = Path()
                        let s = r * 2.2
                        spark.addEllipse(in: CGRect(x: x - s * 0.3, y: y - s * 0.3, width: s, height: s))
                        context.fill(spark, with: .color(secondary.opacity(alpha * 0.35)))
                    }
                }
            }
        }
        .opacity(phase == .revealed ? 0.45 : 0.85)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var starsRow: some View {
        let tint = currentRarity.tint
        return HStack(spacing: 8) {
            ForEach(1...LuckyBoxMockPool.maxStars, id: \.self) { index in
                LuckyStarBadge(
                    filled: index <= stars,
                    emphasized: starBurst && index == stars,
                    gold: tint,
                    orange: currentRarity.particleSecondary
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.42), value: stars)
                .animation(.spring(response: 0.35, dampingFraction: 0.42), value: starBurst)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.28))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.55),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: tint.opacity(0.35), radius: 14, y: 6)
        )
        .animation(.easeInOut(duration: 0.55), value: currentRarity)
        .accessibilityLabel("\(stars) z \(LuckyBoxMockPool.maxStars) hvězd")
    }

    private var chestView: some View {
        ZStack {
            // zavřená bedna (mizí při otevření)
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black.opacity(0.65),
                                Color.black.opacity(0.15),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 44)
                    .offset(y: 120)

                LuckyOpenBurst(progress: lidOpen, gold: gold, tint: currentRarity.tint)
                    .offset(y: -20)
                    .allowsHitTesting(false)

                LuckyHitAura(
                    progress: hitAuraProgress,
                    intense: hitAuraIntense,
                    tint: currentRarity.tint,
                    gold: gold
                )
                .frame(width: 420, height: 420)
                .allowsHitTesting(false)

                LuckyChestRig(lidOpen: lidOpen, rarityTint: currentRarity.tint, gold: gold)
                    .frame(width: 290, height: 290)
                    .scaleEffect(boxScale)
                    .rotation3DEffect(
                        .degrees(boxRotation),
                        axis: (x: 0.12, y: 1, z: 0.04),
                        anchor: .center,
                        anchorZ: 0,
                        perspective: 0.55
                    )
                    .offset(y: boxBounce)
                    .shadow(
                        color: currentRarity.tint.opacity(0.35 + 0.25 * lidOpen + 0.35 * Double(hitAuraProgress)),
                        radius: 26 + 18 * hitAuraProgress,
                        y: 12
                    )

                LuckyShakeParticleLayer(particles: shakeParticles)
                    .frame(width: 420, height: 420)
                    .allowsHitTesting(false)
            }
            .opacity(Double(1 - lidOpen))
            .scaleEffect(1 - lidOpen * 0.12)
            .allowsHitTesting(lidOpen < 0.5)

            // Mythic karta (test5) – 3D, otáčení tahem
            LuckyRewardCardView(
                reward: reward,
                gold: gold,
                isInteractive: rewardCardOpacity > 0.5,
                preloadedImage: rewardCardImage
            )
            .opacity(rewardCardOpacity)
            .scaleEffect(rewardCardScale)
            .allowsHitTesting(rewardCardOpacity > 0.5)
        }
        .frame(height: phase == .revealed || rewardCardOpacity > 0.5 ? 520 : 420)
    }

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 14) {
            if phase == .revealed {
                if let reward {
                    LuckyResultStatusView(reward: reward, gold: gold, orange: orange)
                        .opacity(revealOpacity)
                }
            } else if hasOpenedToday && phase != .opening {
                LuckyResultStatusView(
                    reward: reward ?? LuckyBoxLocalStore.lastReward,
                    gold: gold,
                    orange: orange,
                    fallbackTitle: "Dnes už otevřeno"
                )
            } else {
                clickTokensRow
                    .frame(maxWidth: .infinity)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isClickLocked)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let wave = 0.5 + 0.5 * sin(t * (.pi * 2 / 1.8))
                    let opacity = isClickLocked ? 0.4 : (0.55 + 0.45 * wave)

                    Text(hintText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .opacity(opacity)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100, alignment: .top)
    }

    private var hintText: String {
        switch phase {
        case .charging:
            return "Klepni pro upgrade"
        case .readyToOpen:
            return "Klepni pro otevření"
        case .opening:
            return "Otevírá se…"
        case .revealed:
            return ""
        }
    }

    private var clickTokensRow: some View {
        HStack(spacing: 14) {
            ForEach(0..<LuckyBoxMockPool.maxClicks, id: \.self) { index in
                let usedCount = LuckyBoxMockPool.maxClicks - clicksLeft
                let showCoin = phase == .charging && index >= usedCount

                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    if showCoin {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [gold, orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text("?")
                                    .font(.title3.weight(.black))
                                    .foregroundStyle(Color(red: 0.35, green: 0.12, blue: 0.05))
                            )
                            .shadow(color: orange.opacity(0.45), radius: 6, y: 2)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: clicksLeft)
            }
        }
        .accessibilityLabel("Zbývá \(clicksLeft) pokusů")
    }

    private func restoreRevealedStateIfNeeded() {
        guard LuckyBoxLocalStore.hasOpenedToday, let last = LuckyBoxLocalStore.lastReward else { return }
        guard phase != .revealed || reward == nil else { return }

        hasOpenedToday = true
        reward = last
        stars = last.rarity.stars
        clicksLeft = 0
        phase = .revealed
        revealOpacity = 1
        lidOpen = 1
        rewardCardOpacity = 1
        rewardCardScale = 1
        if let url = last.resolvedImageURL {
            rewardCardImage = CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: Self.rewardCardMaxPixelSize)
        }
    }

    private func resetForTesting() {
        LuckyBoxLocalStore.resetToday()
        hasOpenedToday = false
        reward = nil
        rewardCardImage = nil
        stars = 1
        clicksLeft = LuckyBoxMockPool.maxClicks
        phase = .charging
        revealOpacity = 0
        lidOpen = 0
        boxScale = 1
        boxRotation = 0
        boxBounce = 0
        hitAuraProgress = 0
        hitAuraIntense = false
        flashOpacity = 0
        rewardCardOpacity = 0
        rewardCardScale = 0.72
        isBusy = false
        isClickLocked = false
        shakeParticles.removeAll()
        hitAnimationTask?.cancel()
        hitAnimationTask = nil
        openTask?.cancel()
        openTask = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private static let rewardCardMaxPixelSize: CGFloat = 1200

    @MainActor
    private func ensureRewardCardImageLoaded() async {
        guard let reward else { return }
        if rewardCardImage != nil { return }
        rewardCardImage = await preloadRewardCardImage(for: reward)
    }

    private func preloadRewardCardImage(for reward: LuckyBoxReward) async -> UIImage? {
        guard let url = reward.resolvedImageURL else { return nil }
        if let cached = CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: Self.rewardCardMaxPixelSize) {
            return cached
        }
        return await CollectibleImageCache.shared.image(
            for: url,
            maxPixelSize: Self.rewardCardMaxPixelSize
        )
    }

    /// Jediný vstup pro tap – během animace bedny další klepnutí nebereme.
    @MainActor
    private func handleScreenTap() {
        guard !isBusy, !isClickLocked else { return }
        guard phase != .revealed, phase != .opening else { return }

        switch phase {
        case .charging:
            performUpgradeAttempt()
        case .readyToOpen:
            beginOpenChest()
        case .opening, .revealed:
            break
        }
    }

    @MainActor
    private func beginOpenChest() {
        guard !isBusy, !isClickLocked, phase == .readyToOpen else { return }
        isBusy = true
        phase = .opening
        flashOpacity = 0

        openGeneration += 1
        let generation = openGeneration
        openTask?.cancel()
        openTask = Task { @MainActor in
            await openChest(generation: generation)
            if openGeneration == generation {
                openTask = nil
            }
        }
    }

    @MainActor
    private func performUpgradeAttempt() {
        guard phase == .charging, clicksLeft > 0, !isClickLocked else {
            if clicksLeft == 0, phase == .charging {
                phase = .readyToOpen
            }
            return
        }

        isClickLocked = true
        clicksLeft -= 1

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let chance = LuckyBoxMockPool.upgradeChance(fromStars: stars)
        let upgraded = stars < LuckyBoxMockPool.maxStars && Double.random(in: 0...1) < chance

        if upgraded {
            let usedClicks = LuckyBoxMockPool.maxClicks - clicksLeft
            let nextStars = min(stars + 1, 1 + usedClicks, LuckyBoxMockPool.maxStars)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                stars = nextStars
                starBurst = true
            }
            flashOpacity = 0.35
            withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }

        let finishedClicks = clicksLeft == 0
        hitAnimationTask?.cancel()
        hitAnimationTask = Task { @MainActor in
            await playChestSpin(upgraded: upgraded)
            guard !Task.isCancelled else { return }
            isClickLocked = false
            hitAnimationTask = nil
            if finishedClicks {
                withAnimation(.easeInOut(duration: 0.25)) {
                    phase = .readyToOpen
                }
            }
        }
    }

    /// 3D otočka bedny kolem dokola (osa Y) + aura / částice.
    @MainActor
    private func playChestSpin(upgraded: Bool) async {
        let turns = upgraded ? 2.0 : 1.0
        let spinDuration = upgraded ? 0.78 : 0.58
        let startRotation = boxRotation.truncatingRemainder(dividingBy: 360)
        var noAnim = Transaction()
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            boxRotation = startRotation
            hitAuraProgress = 0
            hitAuraIntense = upgraded
        }

        emitHitParticles(upgraded: upgraded)
        particleBoost = true

        // squash před odletem
        withAnimation(.easeOut(duration: 0.1)) {
            boxScale = upgraded ? 0.86 : 0.9
            boxBounce = 12
            hitAuraProgress = 0.2
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else {
            finishHitMotionCleanup()
            return
        }

        // 3D spin kolem svislé osy (1× / 2×) + expandující aura
        withAnimation(.easeInOut(duration: spinDuration)) {
            boxRotation = startRotation + 360 * turns
            boxScale = upgraded ? 1.16 : 1.1
            boxBounce = upgraded ? -22 : -14
            hitAuraProgress = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(spinDuration * 1_000_000_000))
        guard !Task.isCancelled else {
            finishHitMotionCleanup()
            return
        }

        if upgraded {
            emitHitParticles(upgraded: true, burstExtra: 5)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) {
                boxScale = 1.18
                boxBounce = -14
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                finishHitMotionCleanup()
                return
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                boxScale = 1
                boxBounce = 0
                starBurst = false
                hitAuraProgress = 0
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.64)) {
                boxScale = 1
                boxBounce = 7
            }
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else {
                finishHitMotionCleanup()
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                boxBounce = 0
                hitAuraProgress = 0
            }
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        finishHitMotionCleanup()
    }

    @MainActor
    private func finishHitMotionCleanup() {
        var noAnim = Transaction()
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            boxRotation = boxRotation.truncatingRemainder(dividingBy: 360)
            hitAuraIntense = false
            particleBoost = false
            if hitAuraProgress > 0.01 {
                hitAuraProgress = 0
            }
        }
    }

    @MainActor
    private func emitHitParticles(upgraded: Bool, burstExtra: Int = 0) {
        let now = Date()
        let assets = ["LuckyParticleGold", "LuckyParticleCyan", "LuckyParticleSoft", "LuckyParticleWhite"]
        let count = (upgraded ? 10 : 7) + burstExtra
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .pi * 2 + Double.random(in: -0.2...0.2)
            shakeParticles.append(
                LuckyShakeParticle(
                    assetName: assets[i % assets.count],
                    angle: angle,
                    startRadius: Double.random(in: upgraded ? 70...95 : 78...100),
                    speed: Double.random(in: upgraded ? 55...110 : 40...85),
                    size: CGFloat.random(in: upgraded ? 26...42 : 22...34),
                    spin: Double.random(in: -120...120),
                    startedAt: now,
                    duration: Double.random(in: upgraded ? 0.55...0.85 : 0.45...0.7)
                )
            )
        }
        if shakeParticles.count > 28 {
            shakeParticles.removeFirst(shakeParticles.count - 28)
        }
    }

    @MainActor
    private func openChest(generation: Int) async {
        let stillCurrent = { openGeneration == generation && !Task.isCancelled }

        revealOpacity = 0
        rewardCardOpacity = 0
        rewardCardScale = 0.55
        flashOpacity = 0
        shakeParticles.removeAll()
        hitAnimationTask?.cancel()
        hitAnimationTask = nil
        isClickLocked = false
        boxRotation = 0
        boxScale = 1
        boxBounce = 0
        hitAuraProgress = 0
        hitAuraIntense = false
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let token = authState.authToken
        let chargedStars = min(LuckyBoxMockPool.maxStars, max(1, stars))
        let chargedRarity = LuckyBoxRarity.from(stars: chargedStars)

        let picked: LuckyBoxReward
        do {
            // Shake + API paralelně (API má vlastní timeout 12 s).
            // Nabité hvězdy = cílová rarita dropu (3★ → rare položka z DB).
            async let apiResult = CollectiblesService().openChest(
                token: token,
                luckStars: chargedStars,
                rarity: chargedRarity.rawValue
            )

            for i in 0..<8 {
                guard stillCurrent() else {
                    abortOpen(message: nil, generation: generation)
                    return
                }
                withAnimation(.easeInOut(duration: 0.06)) {
                    boxRotation = (i % 2 == 0) ? -14 : 14
                    boxScale = i % 2 == 0 ? 1.1 : 0.92
                    boxBounce = (i % 2 == 0) ? -8 : 6
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }

            withAnimation(.easeOut(duration: 0.08)) {
                boxRotation = 0
                boxScale = 1.05
                boxBounce = 0
            }
            particleBoost = true

            let result = try await apiResult
            guard stillCurrent() else {
                abortOpen(message: nil, generation: generation)
                return
            }

            // Rarita z nabití hvězd; obsah karty (jméno/foto) z API položky dané rarity.
            picked = LuckyBoxReward(from: result, rarity: chargedRarity)
        } catch is CancellationError {
            abortOpen(message: nil, generation: generation)
            return
        } catch {
            abortOpen(
                message: (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription,
                generation: generation
            )
            return
        }

        guard stillCurrent() else {
            abortOpen(message: nil, generation: generation)
            return
        }

        reward = picked
        stars = chargedStars

        // Fotku stáhneme během celebrace hvězd, ať se při revealu neukáže spinner.
        async let imageLoad = preloadRewardCardImage(for: picked)
        await pulseStarsCelebration()
        let preloaded = await imageLoad

        guard stillCurrent() else {
            abortOpen(message: nil, generation: generation)
            return
        }

        rewardCardImage = preloaded

        withAnimation(.easeIn(duration: 0.12)) {
            flashOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 140_000_000)

        lidOpen = 1
        boxScale = 1
        boxBounce = 0
        rewardCardScale = 0.82
        rewardCardOpacity = 0.01
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        try? await Task.sleep(nanoseconds: 120_000_000)

        withAnimation(.easeOut(duration: 0.45)) {
            flashOpacity = 0
        }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.72)) {
            rewardCardScale = 1.06
            rewardCardOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 380_000_000)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            rewardCardScale = 1
        }

        guard stillCurrent() else {
            abortOpen(message: nil, generation: generation)
            return
        }

        LuckyBoxLocalStore.saveOpen(reward: picked)
        hasOpenedToday = true
        phase = .revealed

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.35)) {
            revealOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        particleBoost = false
        isBusy = false
    }

    @MainActor
    private func abortOpen(message: String?, generation: Int) {
        guard openGeneration == generation else { return }
        particleBoost = false
        flashOpacity = 0
        lidOpen = 0
        rewardCardOpacity = 0
        rewardCardImage = nil
        isClickLocked = false
        withAnimation(.easeOut(duration: 0.2)) {
            boxRotation = 0
            boxScale = 1
            boxBounce = 0
            hitAuraProgress = 0
            hitAuraIntense = false
        }
        phase = .readyToOpen
        isBusy = false
        if let message, !message.isEmpty {
            openErrorMessage = message
            showOpenError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func pulseStarsCelebration() async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
            starBurst = true
        }
        emitHitParticles(upgraded: true)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeOut(duration: 0.2)) { starBurst = false }
    }
}

// MARK: - Share studio

private enum LuckyShareFormat: String, CaseIterable, Identifiable {
    case story
    case square
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "Stories"
        case .square: return "Feed"
        case .card: return "Karta"
        }
    }

    var subtitle: String {
        switch self {
        case .story: return "9∶16 příběh"
        case .square: return "1∶1 příspěvek"
        case .card: return "jen rámeček"
        }
    }

    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .card: return CGSize(width: 1080, height: 1440)
        }
    }
}

private struct LuckyShareStudioView: View {
    let reward: LuckyBoxReward
    let gold: Color
    var preloadedImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<LuckyShareFormat> = [.story, .square, .card]
    @State private var previews: [LuckyShareFormat: UIImage] = [:]
    @State private var activityPayload: LuckySharePayload?
    @State private var statusMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Vyber varianty ke sdílení nebo uložení")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(LuckyShareFormat.allCases) { format in
                        formatRow(format)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(gold)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sdílet kartu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        Task { await shareSelected() }
                    } label: {
                        Label("Sdílet vybrané", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || isBusy)

                    Button {
                        Task { await saveSelectedToPhotos() }
                    } label: {
                        Label("Uložit do fotek", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selected.isEmpty || isBusy)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .sheet(item: $activityPayload) { payload in
                LuckyShareSheet(items: payload.items)
            }
            .task {
                await renderAllPreviews()
            }
        }
    }

    private func formatRow(_ format: LuckyShareFormat) -> some View {
        let isOn = selected.contains(format)
        return Button {
            if isOn {
                selected.remove(format)
            } else {
                selected.insert(format)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .frame(width: 72, height: 96)

                    if let image = previews[format] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        ProgressView()
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isOn ? gold : Color.white.opacity(0.12), lineWidth: isOn ? 2 : 1)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(format.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(format.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? gold : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func renderAllPreviews() async {
        for format in LuckyShareFormat.allCases {
            if let image = render(format: format) {
                previews[format] = image
            }
            await Task.yield()
        }
    }

    @MainActor
    private func render(format: LuckyShareFormat) -> UIImage? {
        let size = format.size
        let content = LuckySharePosterView(
            reward: reward,
            gold: gold,
            format: format,
            preloadedImage: preloadedImage
        )
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage
    }

    @MainActor
    private func selectedImages() -> [UIImage] {
        LuckyShareFormat.allCases.compactMap { format in
            guard selected.contains(format) else { return nil }
            return previews[format] ?? render(format: format)
        }
    }

    @MainActor
    private func shareSelected() async {
        isBusy = true
        defer { isBusy = false }
        let images = selectedImages()
        guard !images.isEmpty else { return }
        let powderBit = reward.duplicate && reward.powderGained > 0
            ? " · +\(reward.powderGained) \(reward.currencyNameOf ?? "hvězdného prachu")"
            : ""
        let text = "Právě jsem v Provikart otevřel Lucky Box a získal \(reward.title) (\(reward.rarity.title))\(powderBit)!"
        activityPayload = LuckySharePayload(items: images + [text])
    }

    @MainActor
    private func saveSelectedToPhotos() async {
        isBusy = true
        defer { isBusy = false }
        let images = selectedImages()
        guard !images.isEmpty else { return }

        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            statusMessage = "Povol přístup k fotkám v Nastavení."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }
            statusMessage = images.count == 1
                ? "Uloženo do Fotky."
                : "Uloženo \(images.count) variant do Fotky."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            statusMessage = "Uložení se nepovedlo."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct LuckySharePosterView: View {
    let reward: LuckyBoxReward
    let gold: Color
    let format: LuckyShareFormat
    var preloadedImage: UIImage? = nil

    private var colors: [Color] { reward.rarity.backgroundColors }

    var body: some View {
        ZStack {
            LinearGradient(colors: colors + [.black], startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [reward.rarity.tint.opacity(0.45), .clear],
                center: .center,
                startRadius: 40,
                endRadius: format == .story ? 700 : 480
            )

            VStack(spacing: format == .square ? 28 : 36) {
                VStack(spacing: 8) {
                    Text("PROVIKART")
                        .font(.system(size: format == .card ? 28 : 34, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.9))

                    Text("LUCKY BOX")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(gold)
                }
                .padding(.top, format == .story ? 120 : 48)

                LuckyRewardCardView(
                    reward: reward,
                    gold: gold,
                    isInteractive: false,
                    preloadedImage: preloadedImage
                )
                    .scaleEffect(format == .card ? 2.05 : 1.8)
                    .frame(width: format == .card ? 820 : 720)
                    .frame(height: format == .card ? 1090 : 960)
                    .shadow(color: .black.opacity(0.45), radius: 40, y: 20)

                if format != .card {
                    VStack(spacing: 10) {
                        Text(reward.rarity.title.uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(reward.rarity.tint)

                        Text("Dnes jsem vytáhl \(reward.title)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text(reward.subtitle)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 64)
                }

                Spacer(minLength: 0)

                Text("Otevři svůj Lucky Box v Provikart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, format == .story ? 100 : 48)
            }
            .padding(.horizontal, 40)
        }
    }
}

private struct LuckySharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct LuckyShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Hit aura (expanding rings around chest)

private struct LuckyHitAura: View {
    let progress: CGFloat
    let intense: Bool
    let tint: Color
    let gold: Color

    var body: some View {
        let p = max(0, min(1, progress))
        ZStack {
            // měkký bloom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55 * Double(1 - p) * (intense ? 1 : 0.7)),
                            gold.opacity(0.4 * Double(1 - p)),
                            tint.opacity(0.28 * Double(1 - p)),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 150 + 40 * p
                    )
                )
                .frame(width: 260 + 90 * p, height: 260 + 90 * p)
                .blendMode(.plusLighter)

            ForEach(0..<3, id: \.self) { index in
                ring(at: index, progress: p)
            }

            // jiskřivé čárky
            ForEach(0..<(intense ? 12 : 8), id: \.self) { index in
                spark(at: index, progress: p)
            }
        }
        .opacity(Double(min(1, p * 2.2)) * Double(1 - p * 0.15))
        .allowsHitTesting(false)
    }

    private func ring(at index: Int, progress: CGFloat) -> some View {
        let stagger = CGFloat(index) * 0.14
        let local = max(0, min(1, (progress - stagger) / max(0.01, 1 - stagger)))
        let size: CGFloat = 140 + local * (110 + CGFloat(index) * 48)
        return Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        Color.white.opacity(0.85),
                        gold.opacity(0.9),
                        tint.opacity(0.75),
                        Color.white.opacity(0.35),
                        gold.opacity(0.8)
                    ],
                    center: .center
                ),
                lineWidth: (intense ? 3.2 : 2.4) - CGFloat(index) * 0.55
            )
            .frame(width: size, height: size)
            .opacity(Double((1 - local) * (intense ? 0.95 : 0.7)))
            .blur(radius: 0.4 + CGFloat(index) * 0.35)
            .rotationEffect(.degrees(Double(local) * (intense ? 55 : 35) * (index.isMultiple(of: 2) ? 1 : -1)))
    }

    private func spark(at index: Int, progress: CGFloat) -> some View {
        let count = intense ? 12.0 : 8.0
        let baseAngle = Double(index) / count * .pi * 2
        let local = max(0, min(1, progress))
        let radius = 70 + local * (95 + Double(index % 3) * 18)
        let x = cos(baseAngle + local * 0.35) * radius
        let y = sin(baseAngle + local * 0.35) * radius * 0.9
        let len: CGFloat = intense ? 16 : 11
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [Color.white, gold.opacity(0.8), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: len + CGFloat(index % 3) * 4, height: 2.2)
            .rotationEffect(.degrees(baseAngle * 180 / .pi + 90))
            .offset(x: x, y: y)
            .opacity(Double((1 - local) * 0.85))
            .blendMode(.plusLighter)
    }
}

// MARK: - AI particle sprites around chest

private struct LuckyShakeParticle: Identifiable, Equatable {
    let id = UUID()
    let assetName: String
    let angle: Double
    let startRadius: Double
    let speed: Double
    let size: CGFloat
    let spin: Double
    let startedAt: Date
    let duration: TimeInterval
}

private struct LuckyShakeParticleLayer: View {
    let particles: [LuckyShakeParticle]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            ZStack {
                ForEach(particles) { particle in
                    LuckyShakeParticleSprite(particle: particle, now: now)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LuckyShakeParticleSprite: View {
    let particle: LuckyShakeParticle
    let now: Date

    var body: some View {
        let age = max(0, now.timeIntervalSince(particle.startedAt))
        let life = min(1, age / max(0.01, particle.duration))
        let visible = age < particle.duration
        let radius = particle.startRadius + age * particle.speed
        let x = cos(particle.angle) * radius
        let y = sin(particle.angle) * radius * 0.82 - age * age * 40
        let fade = max(0, 1 - life)
        let scale = 0.85 + fade * 0.45

        Image(particle.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: particle.size, height: particle.size)
            .rotationEffect(.degrees(particle.spin * life))
            .scaleEffect(scale)
            .opacity(visible ? (0.35 + 0.65 * fade) : 0)
            .blendMode(.screen)
            .offset(x: x, y: y)
            .accessibilityHidden(true)
    }
}

// MARK: - Chest (closed → fade out)

private struct LuckyChestRig: View {
    let lidOpen: CGFloat
    let rarityTint: Color
    let gold: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55 * lidOpen),
                            gold.opacity(0.4 * lidOpen),
                            rarityTint.opacity(0.15 * lidOpen),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 110
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 4)
                .blendMode(.plusLighter)

            Image("LuckyChestClosed")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

struct LuckyRewardCardView: View {
    let reward: LuckyBoxReward?
    let gold: Color
    let isInteractive: Bool
    var preloadedImage: UIImage? = nil

    @State private var dragRotX: Double = 0
    @State private var dragRotY: Double = 0
    @State private var idlePulse = false
    @State private var resolvedImage: UIImage?
    @State private var didFailLoading = false

    private var idleRotX: Double { idlePulse ? 7 : -5 }
    private var idleRotY: Double { idlePulse ? -9 : 8 }
    private var idleScale: CGFloat { idlePulse ? 1.02 : 0.985 }

    private var displayImage: UIImage? {
        preloadedImage ?? resolvedImage
    }

    var body: some View {
        let tilted = cardContent
            .scaleEffect(isInteractive ? idleScale : 1)
            .rotation3DEffect(
                .degrees(idleRotX + dragRotX),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.55
            )
            .rotation3DEffect(
                .degrees(idleRotY + dragRotY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .shadow(
                color: Color.black.opacity(0.35),
                radius: 24,
                x: dragRotY * 0.35,
                y: 12 + dragRotX * 0.2
            )

        Group {
            if isInteractive {
                tilted.gesture(dragGesture)
            } else {
                tilted
            }
        }
        .onAppear {
            syncResolvedImageFromCache()
            guard isInteractive else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                idlePulse = true
            }
        }
        .task(id: reward?.id) {
            await loadImageIfNeeded()
        }
        .onChange(of: preloadedImage) { _, _ in
            syncResolvedImageFromCache()
        }
        .onChange(of: isInteractive) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    idlePulse = true
                }
            } else {
                idlePulse = false
                dragRotX = 0
                dragRotY = 0
            }
        }
    }

    private var cardContent: some View {
        ZStack {
            if let reward {
                fullCardArtwork(for: reward)
            } else {
                questionMarkArtwork
            }
        }
        .frame(maxWidth: 390)
        .frame(height: 520)
    }

    @ViewBuilder
    private func fullCardArtwork(for reward: LuckyBoxReward) -> some View {
        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if reward.resolvedImageURL == nil || didFailLoading {
                questionMarkArtwork
            } else {
                // Bez spinneru – fotka se prefetchuje před reveálem / z cache.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncResolvedImageFromCache() {
        didFailLoading = false
        if let preloadedImage {
            resolvedImage = preloadedImage
            return
        }
        guard let url = reward?.resolvedImageURL else {
            resolvedImage = nil
            return
        }
        resolvedImage = CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: 1200)
    }

    private func loadImageIfNeeded() async {
        if displayImage != nil { return }
        guard let url = reward?.resolvedImageURL else { return }
        let image = await CollectibleImageCache.shared.image(for: url, maxPixelSize: 1200)
        guard !Task.isCancelled else { return }
        if let image {
            resolvedImage = image
            didFailLoading = false
        } else {
            didFailLoading = true
        }
    }

    private var questionMarkArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

            Image(systemName: "questionmark")
                .font(.system(size: 88, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(24)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let nextY = min(28, max(-28, value.translation.width / 7))
                let nextX = min(22, max(-22, -value.translation.height / 8))
                dragRotY = nextY
                dragRotX = nextX
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    dragRotX = 0
                    dragRotY = 0
                }
            }
    }
}

// MARK: - Card info sheet

struct LuckyCardInfoSheet: View {
    let reward: LuckyBoxReward
    let gold: Color
    let orange: Color
    var preloadedImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    LuckyRewardCardView(
                        reward: reward,
                        gold: gold,
                        isInteractive: true,
                        preloadedImage: preloadedImage
                    )
                        .frame(maxWidth: 320)
                        .frame(height: 430)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 0) {
                        detailRow(
                            icon: "seal.fill",
                            title: "Rarita",
                            value: reward.rarity.title,
                            tint: reward.rarity.tint
                        )
                        divider
                        detailRow(
                            icon: "star.fill",
                            title: "Hvězdy",
                            value: "\(reward.rarity.stars) / \(LuckyBoxMockPool.maxStars)",
                            tint: gold
                        )

                        if reward.showsChestOutcome {
                            divider
                            detailRow(
                                icon: reward.duplicate ? "arrow.triangle.2.circlepath" : "plus.circle.fill",
                                title: "Výsledek",
                                value: reward.duplicate ? "Duplicita" : "Nový předmět",
                                tint: reward.duplicate ? orange : Color(red: 0.45, green: 0.9, blue: 0.65)
                            )
                        }

                        divider
                        detailRow(
                            icon: reward.isOwned ? "square.stack.3d.up.fill" : "lock.fill",
                            title: "Stav",
                            value: reward.isOwned
                                ? "Ve sbírce ×\(max(1, reward.qty))"
                                : "Nezískáno",
                            tint: reward.isOwned ? .primary : .secondary
                        )

                        if let need = reward.powderNeed, need > 0, !reward.isOwned {
                            divider
                            detailRow(
                                icon: "sparkles",
                                title: "Potřeba prachu",
                                value: "\(need)",
                                tint: gold
                            )
                        }

                        if reward.duplicate, reward.powderGained > 0 {
                            divider
                            detailRow(
                                icon: "sparkles",
                                title: "Získáno",
                                value: "+\(reward.powderGained) \(reward.currencyNameOf ?? "hvězdného prachu")",
                                tint: gold
                            )
                        }

                        if let balance = reward.balance {
                            divider
                            detailRow(
                                icon: "sparkles",
                                title: "Zůstatek prachu",
                                value: "\(balance)",
                                tint: gold
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 20)

                    if !reward.subtitle.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Popis")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(reward.subtitle)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 20)
                    }

                    if let message = reward.message, !message.isEmpty, message != reward.subtitle {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(reward.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var divider: some View {
        Divider().padding(.leading, 52)
    }

    private func detailRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Result status / badges

private struct LuckyResultStatusView: View {
    let reward: LuckyBoxReward?
    let gold: Color
    let orange: Color
    var fallbackTitle: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            if let reward {
                if reward.duplicate {
                    duplicateBlock(reward)
                } else {
                    newItemBlock(reward)
                }
            } else if let fallbackTitle {
                Text(fallbackTitle)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func duplicateBlock(_ reward: LuckyBoxReward) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.bold))
                Text("DUPLICITA")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(orange.opacity(0.18)))
            .overlay(Capsule().stroke(orange.opacity(0.35), lineWidth: 1))

            if reward.powderGained > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.body.weight(.semibold))
                    Text("+\(reward.powderGained)")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                    Text(reward.currencyNameOf ?? "hvězdného prachu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(gold)
            }

            Text("Ve sbírce ×\(max(1, reward.qty))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func newItemBlock(_ reward: LuckyBoxReward) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.caption.weight(.bold))
                Text("NOVÝ PŘEDMĚT")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(gold.opacity(0.16)))
            .overlay(Capsule().stroke(gold.opacity(0.35), lineWidth: 1))

            Text(reward.title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

struct LuckyCardOutcomeBadge: View {
    let reward: LuckyBoxReward
    let gold: Color

    var body: some View {
        Group {
            if reward.showsChestOutcome {
                if reward.duplicate, reward.powderGained > 0 {
                    HStack(spacing: 8) {
                        statusPill(
                            icon: "arrow.triangle.2.circlepath",
                            text: "Duplicita",
                            tint: Color(red: 1.0, green: 0.62, blue: 0.28)
                        )
                        statusPill(
                            icon: "sparkles",
                            text: "+\(reward.powderGained)",
                            tint: gold
                        )
                    }
                } else if reward.duplicate {
                    statusPill(
                        icon: "arrow.triangle.2.circlepath",
                        text: "×\(max(1, reward.qty))",
                        tint: Color(red: 1.0, green: 0.62, blue: 0.28)
                    )
                } else {
                    statusPill(
                        icon: "plus.circle.fill",
                        text: "Nový",
                        tint: Color(red: 0.45, green: 0.9, blue: 0.65)
                    )
                }
            } else if reward.isOwned {
                statusPill(
                    icon: "checkmark.circle.fill",
                    text: reward.qty > 1 ? "×\(reward.qty)" : "Vlastněno",
                    tint: Color(red: 0.45, green: 0.9, blue: 0.65)
                )
            } else {
                statusPill(
                    icon: "lock.fill",
                    text: "Zamčeno",
                    tint: .secondary
                )
            }
        }
    }

    private func statusPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.16))
                .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
        )
    }
}

private struct LuckyOpenBurst: View {
    let progress: CGFloat
    let gold: Color
    let tint: Color

    var body: some View {
        ZStack {
            rays
            core
        }
        .opacity(Double(min(1, progress * 1.2)))
        .allowsHitTesting(false)
    }

    private var rays: some View {
        ForEach(0..<8, id: \.self) { index in
            ray(at: index)
        }
    }

    private func ray(at index: Int) -> some View {
        let width = 6 + CGFloat(index % 3) * 2
        let height = 90 + CGFloat(index % 3) * 22
        let angle = Double(index) * 12 - 42
        return Capsule()
            .fill(rayGradient)
            .frame(width: width, height: height)
            .offset(y: -40)
            .rotationEffect(.degrees(angle))
            .opacity(Double(progress) * 0.7)
            .blur(radius: 0.8)
    }

    private var rayGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.4 * progress),
                gold.opacity(0.28 * progress),
                .clear
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var core: some View {
        Circle()
            .fill(coreGradient)
            .frame(width: 140, height: 140)
            .scaleEffect(0.6 + 0.4 * progress)
            .blur(radius: 3)
            .blendMode(.plusLighter)
    }

    private var coreGradient: RadialGradient {
        RadialGradient(
            colors: [
                Color.white.opacity(0.55 * progress),
                gold.opacity(0.35 * progress),
                tint.opacity(0.12 * progress),
                .clear
            ],
            center: .center,
            startRadius: 2,
            endRadius: 70
        )
    }
}

private struct LuckyStarBadge: View {
    let filled: Bool
    let emphasized: Bool
    let gold: Color
    let orange: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(filled ? 0.22 : 0.08),
                            Color.black.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: filled
                                    ? [gold.opacity(0.95), orange.opacity(0.55)]
                                    : [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: filled ? gold.opacity(0.55) : .clear, radius: emphasized ? 14 : 6, y: 2)

            if filled {
                Image(systemName: "star.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, gold, orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: orange.opacity(0.7), radius: 4, y: 1)
            } else {
                Image(systemName: "star")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.28))
            }
        }
    }
}

private struct LuckySoftFloor: View {
    let accent: Color
    var intensity: Double = 0.3

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let horizon = size.height * 0.58
                for i in 0..<12 {
                    let t = CGFloat(i) / 11
                    let y = horizon + pow(t, 1.55) * (size.height - horizon)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(
                        path,
                        with: .color(accent.opacity(0.04 + 0.14 * t * intensity)),
                        lineWidth: 1
                    )
                }
                for i in 0...12 {
                    let u = CGFloat(i) / 12
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * (0.5 + (u - 0.5) * 0.2), y: horizon))
                    path.addLine(to: CGPoint(x: size.width * (0.5 + (u - 0.5) * 1.3), y: size.height))
                    context.stroke(
                        path,
                        with: .color(accent.opacity(0.03 + 0.05 * intensity)),
                        lineWidth: 1
                    )
                }
            }
            .mask(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45), .black],
                    startPoint: UnitPoint(x: 0.5, y: 0.52),
                    endPoint: .bottom
                )
            )
        }
        .animation(.easeInOut(duration: 0.7), value: intensity)
    }
}

// MARK: - Home entry helpers

enum LuckyBoxHomeStatus {
    case ready
    case opened(countdown: String)

    static func current(now: Date = Date()) -> LuckyBoxHomeStatus {
        if LuckyBoxLocalStore.hasOpenedToday {
            return .opened(countdown: LuckyBoxLocalStore.countdownText(reference: now))
        }
        return .ready
    }
}

#Preview {
    NavigationStack {
        LuckyBoxView()
    }
}
