//
//  LuckyBoxView.swift
//  Provikart
//
//  Lucky Box – denní bedna + bonus a drop luck za včerejší usazený výkon.
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

    /// Smalt truhly podle rarity.
    var enamel: Color {
        switch self {
        case .common: return Color(red: 0.10, green: 0.78, blue: 0.97)
        case .uncommon: return Color(red: 0.18, green: 0.86, blue: 0.62)
        case .rare: return Color(red: 0.62, green: 0.38, blue: 0.98)
        case .epic: return Color(red: 0.96, green: 0.62, blue: 0.14)
        case .legendary: return Color(red: 0.96, green: 0.22, blue: 0.32)
        }
    }

    var enamelDeep: Color {
        switch self {
        case .common: return Color(red: 0.05, green: 0.46, blue: 0.68)
        case .uncommon: return Color(red: 0.06, green: 0.48, blue: 0.38)
        case .rare: return Color(red: 0.32, green: 0.12, blue: 0.62)
        case .epic: return Color(red: 0.58, green: 0.28, blue: 0.06)
        case .legendary: return Color(red: 0.58, green: 0.08, blue: 0.14)
        }
    }

    /// Základ kosočtvercového arénového pozadí / podlahy.
    var arenaTint: Color {
        switch self {
        case .common: return Color(red: 0.14, green: 0.38, blue: 0.64)
        case .uncommon: return Color(red: 0.10, green: 0.46, blue: 0.42)
        case .rare: return Color(red: 0.36, green: 0.16, blue: 0.58)
        case .epic: return Color(red: 0.58, green: 0.34, blue: 0.10)
        case .legendary: return Color(red: 0.58, green: 0.12, blue: 0.18)
        }
    }

    var arenaImageName: String {
        switch self {
        case .common: return "LuckyBoxArenaCommon"
        case .uncommon: return "LuckyBoxArenaUncommon"
        case .rare: return "LuckyBoxArenaRare"
        case .epic: return "LuckyBoxArenaEpic"
        case .legendary: return "LuckyBoxArenaLegendary"
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

struct LuckyBoxDayDrop: Identifiable, Codable, Equatable {
    let slot: Int
    let reward: LuckyBoxReward
    var id: String { "slot-\(slot)-\(reward.id)" }
}

enum LuckyBoxLocalStore {
    private static let dayKey = "lucky_box_last_open_day"
    private static let rewardKey = "lucky_box_last_reward"
    private static let rewardsKey = "lucky_box_today_rewards"
    private static let openedCountKey = "lucky_box_opened_count"
    private static let settledDayKey = "lucky_box_settled_day"
    private static let yesterdayCountKey = "lucky_box_services_yesterday"
    private static let todayCountKey = "lucky_box_services_today"

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

    static var openedCountToday: Int {
        guard UserDefaults.standard.string(forKey: dayKey) == todayKey() else { return 0 }
        let stored = UserDefaults.standard.integer(forKey: openedCountKey)
        if stored > 0 { return stored }
        return 1
    }

    static var hasOpenedToday: Bool {
        openedCountToday > 0
    }

    /// Auto-ukázat jen první (ranní) bednu, bonusové si uživatel otevře sám.
    static var shouldAutoPresent: Bool {
        openedCountToday == 0
    }

    static var lastReward: LuckyBoxReward? {
        todayDrops.last?.reward ?? {
            guard let data = UserDefaults.standard.data(forKey: rewardKey) else { return nil }
            return try? JSONDecoder().decode(LuckyBoxReward.self, from: data)
        }()
    }

    static var todayDrops: [LuckyBoxDayDrop] {
        guard UserDefaults.standard.string(forKey: dayKey) == todayKey() else { return [] }
        if let data = UserDefaults.standard.data(forKey: rewardsKey),
           let list = try? JSONDecoder().decode([LuckyBoxDayDrop].self, from: data),
           !list.isEmpty {
            return list
        }
        if let data = UserDefaults.standard.data(forKey: rewardKey),
           let last = try? JSONDecoder().decode(LuckyBoxReward.self, from: data) {
            return [LuckyBoxDayDrop(slot: max(1, openedCountToday), reward: last)]
        }
        return []
    }

    static var cachedYesterdayServices: Int {
        guard UserDefaults.standard.string(forKey: settledDayKey) == todayKey() else { return 0 }
        return UserDefaults.standard.integer(forKey: yesterdayCountKey)
    }

    static var cachedTodayServices: Int {
        guard UserDefaults.standard.string(forKey: settledDayKey) == todayKey() else { return 0 }
        return UserDefaults.standard.integer(forKey: todayCountKey)
    }

    static func savePerformance(yesterday: Int, today: Int, on date: Date = Date()) {
        UserDefaults.standard.set(todayKey(reference: date), forKey: settledDayKey)
        UserDefaults.standard.set(yesterday, forKey: yesterdayCountKey)
        UserDefaults.standard.set(today, forKey: todayCountKey)
    }

    private static let chargeSessionKey = "lucky_box_charge_session"

    private struct ChargeSession: Codable {
        var day: String
        var slot: Int
        var stars: Int
        var clicksLeft: Int
        var phase: String
    }

    static var hasActiveChargeSession: Bool {
        activeChargeSession() != nil
    }

    static func activeChargeSession() -> (stars: Int, clicksLeft: Int, isReadyToOpen: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: chargeSessionKey),
              let session = try? JSONDecoder().decode(ChargeSession.self, from: data),
              session.day == todayKey()
        else { return nil }
        let nextSlot = openedCountToday + 1
        guard session.slot == nextSlot else { return nil }
        return (session.stars, session.clicksLeft, session.phase == "readyToOpen")
    }

    static func saveChargeSession(stars: Int, clicksLeft: Int, readyToOpen: Bool) {
        let session = ChargeSession(
            day: todayKey(),
            slot: openedCountToday + 1,
            stars: stars,
            clicksLeft: clicksLeft,
            phase: readyToOpen ? "readyToOpen" : "charging"
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: chargeSessionKey)
        }
    }

    static func clearChargeSession() {
        UserDefaults.standard.removeObject(forKey: chargeSessionKey)
    }

    static func saveOpen(reward: LuckyBoxReward, on date: Date = Date()) {
        let day = todayKey(reference: date)
        let previousDay = UserDefaults.standard.string(forKey: dayKey)
        let stored = UserDefaults.standard.integer(forKey: openedCountKey)
        let current = previousDay == day ? (stored > 0 ? stored : 1) : 0
        var drops = previousDay == day ? todayDrops : []
        drops.append(LuckyBoxDayDrop(slot: current + 1, reward: reward))
        UserDefaults.standard.set(day, forKey: dayKey)
        UserDefaults.standard.set(current + 1, forKey: openedCountKey)
        if let data = try? JSONEncoder().encode(drops) {
            UserDefaults.standard.set(data, forKey: rewardsKey)
        }
        if let data = try? JSONEncoder().encode(reward) {
            UserDefaults.standard.set(data, forKey: rewardKey)
        }
        clearChargeSession()
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

    /// Šance na +1 hvězdu (raritu) při klepnutí. `luckMultiplier` z včerejšího usazeného výkonu.
    /// Common má nejvyšší drop při startu 1★. Od 5 služeb start na 2★, od 7 na 3★.
    static func upgradeChance(fromStars: Int, luckMultiplier: Double = 1) -> Double {
        let base: Double
        switch fromStars {
        case 1: base = 0.14 // → uncommon
        case 2: base = 0.12 // → rare
        case 3: base = 0.12 // → epic
        case 4: base = 0.07 // → legendary
        default: return 0
        }
        return min(0.26, base * max(1, luckMultiplier))
    }
}

// MARK: - View

struct LuckyBoxView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: LuckyBoxPhase
    @State private var stars: Int
    @State private var clicksLeft: Int
    @State private var reward: LuckyBoxReward?
    @State private var todayDrops: [LuckyBoxDayDrop]
    @State private var galleryIndex: Int
    @State private var hasOpenedToday: Bool
    @ObservedObject private var chestController = LuckyChestController.shared
    @State private var revealOpacity: Double
    @State private var flashOpacity: Double = 0
    @State private var starBurst = false
    @State private var isBusy = false
    /// Zámek mezi klepnutími – dokud se bedna otáčí / třese.
    @State private var isClickLocked = false
    @State private var countdownTick = Date()
    @State private var hitAnimationTask: Task<Void, Never>?
    @State private var rewardCardScale: CGFloat
    @State private var rewardCardOpacity: Double
    @State private var rewardCardImage: UIImage?
    @State private var shareReward: LuckyBoxReward?
    @State private var infoReward: LuckyBoxReward?
    @State private var showTomorrowInfo = false
    @State private var openErrorMessage: String?
    @State private var showOpenError = false
    @State private var openTask: Task<Void, Never>?
    /// Po neúspěšném API otevření lze odejít – jinak by zámek držel uživatele na obrazovce.
    @State private var allowsLeavingAfterError = false
    /// Pořadové číslo otevření – staré (zrušené) tasky nesmí měnit stav.
    @State private var openGeneration = 0
    @ObservedObject private var quota = LuckyBoxQuotaState.shared

    private let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
    private let orange = Color(red: 0.97, green: 0.58, blue: 0.12)

    init() {
        let remaining = LuckyBoxQuotaState.shared.remaining
        let opened = LuckyBoxLocalStore.hasOpenedToday
        let drops = LuckyBoxLocalStore.todayDrops
        let last = drops.last?.reward ?? LuckyBoxLocalStore.lastReward
        _todayDrops = State(initialValue: drops)
        _galleryIndex = State(initialValue: max(0, drops.count - 1))
        _hasOpenedToday = State(initialValue: opened)

        if remaining <= 0, opened, let last {
            _phase = State(initialValue: .revealed)
            _reward = State(initialValue: last)
            _stars = State(initialValue: last.rarity.stars)
            _clicksLeft = State(initialValue: 0)
            _revealOpacity = State(initialValue: 1)
            _rewardCardOpacity = State(initialValue: 1)
            _rewardCardScale = State(initialValue: 1)
            if let url = last.resolvedImageURL {
                _rewardCardImage = State(initialValue: CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: 1200))
            } else {
                _rewardCardImage = State(initialValue: nil)
            }
        } else if let session = LuckyBoxLocalStore.activeChargeSession() {
            _phase = State(initialValue: session.isReadyToOpen ? .readyToOpen : .charging)
            _reward = State(initialValue: nil)
            _stars = State(initialValue: session.stars)
            _clicksLeft = State(initialValue: session.clicksLeft)
            _revealOpacity = State(initialValue: 0)
            _rewardCardOpacity = State(initialValue: 0)
            _rewardCardScale = State(initialValue: 0.72)
            _rewardCardImage = State(initialValue: nil)
        } else {
            _phase = State(initialValue: .charging)
            _reward = State(initialValue: nil)
            _stars = State(initialValue: LuckyBoxQuotaState.shared.startingStars)
            _clicksLeft = State(initialValue: LuckyBoxMockPool.maxClicks)
            _revealOpacity = State(initialValue: 0)
            _rewardCardOpacity = State(initialValue: 0)
            _rewardCardScale = State(initialValue: 0.72)
            _rewardCardImage = State(initialValue: nil)
        }
    }

    private var displayedReward: LuckyBoxReward? {
        if phase == .revealed, todayDrops.indices.contains(galleryIndex) {
            return todayDrops[galleryIndex].reward
        }
        return reward
    }

    private var currentRarity: LuckyBoxRarity {
        // Během nabíjení řídí atmosféru hvězdy; po reveal karty rarity z odměny
        if phase == .revealed, let displayedReward {
            return displayedReward.rarity
        }
        return LuckyBoxRarity.from(stars: stars)
    }

    /// Dokud tahle bedna není otevřená, nelze odejít a přerollovat hvězdy.
    /// Po chybě API zámek uvolníme, ať uživatel není uvězněný na obrazovce.
    private var isChestLocked: Bool {
        if allowsLeavingAfterError { return false }
        return phase == .charging || phase == .readyToOpen || phase == .opening || isBusy
    }

    var body: some View {
        ZStack {
            Color(uiColor: LuckyChestController.stageBackground)
                .ignoresSafeArea()

            Image(currentRarity.arenaImageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.45), value: currentRarity)

            LuckyChestStageView(controller: chestController, onTap: handleScreenTap)
                .ignoresSafeArea()
                .opacity(chestController.isLive ? 1 : 0)
                .allowsHitTesting(phase != .revealed && rewardCardOpacity < 0.5 && chestController.isLive)

            if phase != .revealed, !chestController.isLive {
                LuckyChestPlaceholderView(rarity: currentRarity)
                    .ignoresSafeArea()
                if let preview = chestController.previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }

            VStack(spacing: 0) {
                if phase != .revealed {
                    VStack(spacing: 8) {
                        if chestTotal > 1 {
                            chestProgressRow
                        }
                        starsRow
                    }
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
                    .frame(height: phase == .revealed || (hasOpenedToday && phase != .opening) ? 140 : 100)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.35), value: phase)
            .allowsHitTesting(phase == .revealed && rewardCardOpacity > 0.5)
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    bottomSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard phase == .revealed, quota.remaining > 0 else { return }
                    prepareNextChest()
                }
                .allowsHitTesting(phase == .revealed && quota.remaining > 0)
                .transaction { $0.animation = nil }
            }

            // flash musí být navrchu – zakryje bednu i UI
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarStatus
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Info", systemImage: "info.circle") {
                    showTomorrowInfo = true
                }
                .accessibilityLabel("Jak fungují další bedny")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if phase == .revealed, let displayedReward {
                    Button("Karta", systemImage: "rectangle.portrait") {
                        infoReward = displayedReward
                    }
                    .accessibilityLabel("Detail karty")

                    Button("Sdílet", systemImage: "square.and.arrow.up") {
                        shareReward = displayedReward
                    }
                    .accessibilityLabel("Sdílet kartu kamarádům")
                }
            }
        }
        .navigationBarBackButtonHidden(isChestLocked)
        .preference(key: LuckyBoxAllowsLeavingKey.self, value: !isChestLocked)
        .background(LuckyBoxSwipeBackLock(isLocked: isChestLocked))
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showTomorrowInfo) {
            LuckyBoxTomorrowInfoSheet(quota: quota, gold: gold, orange: orange)
        }
        .sheet(item: $shareReward) { reward in
            LuckyShareStudioView(reward: reward, gold: gold, preloadedImage: galleryPreloadedImage(for: reward))
        }
        .sheet(item: $infoReward) { reward in
            LuckyCardInfoSheet(reward: reward, gold: gold, orange: orange, preloadedImage: galleryPreloadedImage(for: reward))
        }
        .alert("Bednu se nepodařilo otevřít", isPresented: $showOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openErrorMessage ?? "Zkus to znovu.")
        }
        .onAppear {
            LuckyChestController.shared.resumeIfNeeded()
            restoreRevealedStateIfNeeded()
            if phase != .revealed {
                chestController.scene.resetToClosed()
            }
            LuckyChestController.shared.resumeIfNeeded()
            syncChestScene()
        }
        .task {
            await quota.refresh(token: authState.authToken, forceOrders: true)
            hasOpenedToday = LuckyBoxLocalStore.hasOpenedToday
            restoreRevealedStateIfNeeded()
            if phase == .charging, stars < quota.startingStars {
                stars = quota.startingStars
            }
        }
        .onChange(of: currentRarity) { _, _ in
            syncChestScene()
        }
        .onChange(of: phase) { _, _ in
            syncChestScene()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            LuckyChestController.shared.resumeIfNeeded()
        }
        .onChange(of: galleryIndex) { _, index in
            applyGallerySelection(index)
        }
        .task(id: reward?.id) {
            await ensureRewardCardImageLoaded()
        }
        .task(id: todayDrops.map(\.id).joined(separator: "|")) {
            await prefetchTodayDropImages()
        }
        .task(id: phase == .revealed) {
            while !Task.isCancelled {
                countdownTick = Date()
                let interval: UInt64 = phase == .revealed ? 1_000_000_000 : 30_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private var chestTotal: Int {
        max(1, quota.earned)
    }

    private var currentChestNumber: Int {
        if phase == .revealed {
            return max(1, min(quota.opened, chestTotal))
        }
        return min(chestTotal, quota.opened + 1)
    }

    private var toolbarStatus: some View {
        VStack(spacing: 1) {
            if phase == .revealed, quota.remaining <= 0 {
                Text("DALŠÍ ZA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(LuckyBoxLocalStore.countdownText(reference: countdownTick))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            } else if phase == .revealed {
                Text("OTEVŘENO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(quota.opened) z \(chestTotal)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            } else {
                Text("BEDNA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(currentChestNumber) z \(chestTotal)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toolbarAccessibilityLabel)
    }

    private var toolbarAccessibilityLabel: String {
        if phase == .revealed, quota.remaining <= 0 {
            return "Další bedna za \(LuckyBoxLocalStore.countdownText(reference: countdownTick))"
        }
        if phase == .revealed {
            return "Otevřeno \(quota.opened) z \(chestTotal) beden"
        }
        return "Bedna \(currentChestNumber) z \(chestTotal)"
    }

    private var chestProgressRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(1...chestTotal, id: \.self) { index in
                    chestProgressDot(index)
                }
            }
            Text("\(currentChestNumber) z \(chestTotal)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bedna \(currentChestNumber) z \(chestTotal)")
    }

    private func chestProgressDot(_ index: Int) -> some View {
        let opened = index <= quota.opened
        let current = phase != .revealed && index == quota.opened + 1
        return Image(systemName: opened || current ? "gift.fill" : "gift")
            .font(.caption.weight(.bold))
            .foregroundStyle(current ? gold : opened ? gold.opacity(0.75) : Color.white.opacity(0.32))
            .scaleEffect(current ? 1.12 : 1)
            .shadow(color: current ? gold.opacity(0.45) : .clear, radius: 5)
            .accessibilityHidden(true)
    }

    private func tapHint(text: String) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isClickLocked || text.isEmpty)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = 0.5 + 0.5 * sin(t * (.pi * 2 / 1.8))
            let opacity = isClickLocked ? 0.4 : (0.55 + 0.45 * wave)

            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .opacity(text.isEmpty ? 0 : opacity)
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
        .accessibilityLabel(text)
    }

    private var starsRow: some View {
        let tint = currentRarity.tint
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
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
            if quota.luckPercent > 0, phase == .charging || phase == .readyToOpen {
                Text("+\(quota.luckPercent) % drop za včerejšek")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(gold)
                    .opacity(0.92)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: currentRarity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(starsAccessibilityLabel)
    }

    private var starsAccessibilityLabel: String {
        if quota.luckPercent > 0 {
            return "\(stars) z \(LuckyBoxMockPool.maxStars) hvězd, plus \(quota.luckPercent) procent k dropu za včerejšek"
        }
        return "\(stars) z \(LuckyBoxMockPool.maxStars) hvězd"
    }

    private var chestView: some View {
        Group {
            if phase == .revealed, todayDrops.count > 1 {
                todayCardsGallery
            } else {
                LuckyRewardCardView(
                    reward: reward,
                    gold: gold,
                    isInteractive: rewardCardOpacity > 0.5,
                    preloadedImage: rewardCardImage
                )
            }
        }
        .opacity(rewardCardOpacity)
        .allowsHitTesting(rewardCardOpacity > 0.5)
        .frame(height: phase == .revealed || rewardCardOpacity > 0.5 ? 560 : 380)
    }

    private var todayCardsGallery: some View {
        VStack(spacing: 8) {
            TabView(selection: $galleryIndex) {
                ForEach(Array(todayDrops.enumerated()), id: \.element.id) { index, drop in
                    LuckyRewardCardView(
                        reward: drop.reward,
                        gold: gold,
                        isInteractive: false,
                        preloadedImage: galleryPreloadedImage(for: drop.reward)
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 520)
            .onAppear {
                if !todayDrops.isEmpty {
                    galleryIndex = min(max(galleryIndex, 0), todayDrops.count - 1)
                }
            }

            galleryPageIndicator
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dnešní otevřené karty")
        .accessibilityHint("Táhni doleva nebo doprava")
    }

    private var galleryPageIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                ForEach(todayDrops.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == galleryIndex ? gold : Color.white.opacity(0.35))
                        .frame(width: index == galleryIndex ? 18 : 7, height: 7)
                        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: galleryIndex)
                }
            }
            Text("\(galleryIndex + 1) / \(todayDrops.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Karta \(galleryIndex + 1) z \(todayDrops.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                galleryIndex = min(galleryIndex + 1, todayDrops.count - 1)
            case .decrement:
                galleryIndex = max(galleryIndex - 1, 0)
            @unknown default:
                break
            }
        }
    }

    private func galleryPreloadedImage(for reward: LuckyBoxReward) -> UIImage? {
        if reward.id == self.reward?.id, let rewardCardImage {
            return rewardCardImage
        }
        guard let url = reward.resolvedImageURL else { return nil }
        return CollectibleImageCache.shared.bestCachedImage(for: url)
    }

    private func syncChestScene() {
        chestController.scene.applyRarity(currentRarity, revealed: phase == .revealed)
    }

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 14) {
            if phase == .revealed {
                if let displayedReward {
                    LuckyResultStatusView(reward: displayedReward, gold: gold, orange: orange)
                        .opacity(revealOpacity)
                    if quota.remaining > 0 {
                        chestProgressRow
                            .opacity(revealOpacity)
                        tapHint(text: "Klepni pro další bednu")
                            .opacity(revealOpacity)
                        if todayDrops.count > 1 {
                            Text("Táhni do stran mezi dnešními kartami")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                                .opacity(revealOpacity)
                        }
                    } else if todayDrops.count > 1 {
                        tapHint(text: "Táhni do stran")
                            .opacity(revealOpacity)
                    }
                }
            } else if quota.remaining <= 0 && hasOpenedToday && phase != .opening {
                LuckyResultStatusView(
                    reward: displayedReward ?? LuckyBoxLocalStore.lastReward,
                    gold: gold,
                    orange: orange,
                    fallbackTitle: "Dnes už otevřeno"
                )
            } else {
                clickTokensRow
                    .frame(maxWidth: .infinity)

                tapHint(text: hintText)
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
        guard quota.remaining <= 0 else { return }
        let drops = LuckyBoxLocalStore.todayDrops
        guard LuckyBoxLocalStore.hasOpenedToday, let last = drops.last?.reward ?? LuckyBoxLocalStore.lastReward else { return }
        guard phase != .revealed || reward == nil || todayDrops.count != drops.count else { return }

        todayDrops = drops
        galleryIndex = max(0, drops.count - 1)
        hasOpenedToday = true
        reward = last
        stars = last.rarity.stars
        clicksLeft = 0
        phase = .revealed
        revealOpacity = 1
        rewardCardOpacity = 1
        rewardCardScale = 1
        if let url = last.resolvedImageURL {
            rewardCardImage = CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: Self.rewardCardMaxPixelSize)
        }
    }

    @MainActor
    private func prepareNextChest() {
        guard quota.remaining > 0, !isBusy else { return }
        isBusy = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.22)) {
            revealOpacity = 0
            rewardCardOpacity = 0
            rewardCardScale = 0.86
        }
        LuckyBoxLocalStore.clearChargeSession()
        reward = nil
        rewardCardImage = nil
        stars = quota.startingStars
        clicksLeft = LuckyBoxMockPool.maxClicks
        phase = .charging
        flashOpacity = 0
        rewardCardScale = 0.72
        isClickLocked = false
        hitAnimationTask?.cancel()
        hitAnimationTask = nil
        openTask?.cancel()
        openTask = nil
        chestController.scene.resetToClosed()
        LuckyChestController.shared.resumeIfNeeded()
        isBusy = false
    }

    private static let rewardCardMaxPixelSize: CGFloat = 1200

    @MainActor
    private func ensureRewardCardImageLoaded() async {
        guard let reward else { return }
        if rewardCardImage != nil { return }
        rewardCardImage = await preloadRewardCardImage(for: reward)
    }

    @MainActor
    private func applyGallerySelection(_ index: Int) {
        guard todayDrops.indices.contains(index) else { return }
        let selected = todayDrops[index].reward
        reward = selected
        stars = selected.rarity.stars
        if let url = selected.resolvedImageURL {
            rewardCardImage = CollectibleImageCache.shared.bestCachedImage(for: url)
        } else {
            rewardCardImage = nil
        }
    }

    @MainActor
    private func prefetchTodayDropImages() async {
        for drop in todayDrops {
            _ = await preloadRewardCardImage(for: drop.reward)
        }
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
        if phase == .revealed, quota.remaining > 0 {
            prepareNextChest()
            return
        }
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
        flashOpacity = 0

        openGeneration += 1
        let generation = openGeneration
        openTask?.cancel()
        openTask = Task { @MainActor in
            await quota.refresh(token: authState.authToken, forceOrders: true)
            guard openGeneration == generation, !Task.isCancelled else { return }

            let nextSlot = LuckyBoxLocalStore.openedCountToday + 1
            if nextSlot > 1, nextSlot > quota.earned {
                isBusy = false
                allowsLeavingAfterError = true
                openErrorMessage = "Zrušené služby se do Lucky Boxu nepočítají, takže tahle bonusová bedna už neplatí."
                showOpenError = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                if openGeneration == generation {
                    openTask = nil
                }
                return
            }

            phase = .opening
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

        let chance = LuckyBoxMockPool.upgradeChance(fromStars: stars, luckMultiplier: quota.luckMultiplier)
        let upgraded = stars < LuckyBoxMockPool.maxStars && Double.random(in: 0...1) < chance
        var newStars = stars

        if upgraded {
            let usedClicks = LuckyBoxMockPool.maxClicks - clicksLeft
            let nextStars = min(stars + 1, quota.startingStars + usedClicks, LuckyBoxMockPool.maxStars)
            newStars = nextStars
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
        LuckyBoxLocalStore.saveChargeSession(
            stars: newStars,
            clicksLeft: clicksLeft,
            readyToOpen: finishedClicks
        )
        hitAnimationTask?.cancel()
        hitAnimationTask = Task { @MainActor in
            await playChestHit(upgraded: upgraded)
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

    @MainActor
    private func playChestHit(upgraded: Bool) async {
        await chestController.scene.playHit(upgraded: upgraded)
        if upgraded {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                starBurst = false
            }
        }
    }

    @MainActor
    private func openChest(generation: Int) async {
        let stillCurrent = { openGeneration == generation && !Task.isCancelled }

        revealOpacity = 0
        rewardCardOpacity = 0
        rewardCardScale = 0.55
        flashOpacity = 0
        hitAnimationTask?.cancel()
        hitAnimationTask = nil
        isClickLocked = false
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
                rarity: chargedRarity.rawValue,
                source: LuckyBoxLocalStore.openedCountToday == 0 ? "daily" : "performance",
                slot: LuckyBoxLocalStore.openedCountToday + 1
            )

            await chestController.scene.playOpenAnticipation()
            guard stillCurrent() else {
                abortOpen(message: nil, generation: generation)
                return
            }

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

        await chestController.scene.playLidOpen()
        guard stillCurrent() else {
            abortOpen(message: nil, generation: generation)
            return
        }

        withAnimation(.easeIn(duration: 0.14)) {
            flashOpacity = 0.42
        }
        async let openExit: Void = chestController.scene.playOpenExit()

        rewardCardScale = 0.42
        rewardCardOpacity = 0.01
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        try? await Task.sleep(nanoseconds: 80_000_000)

        withAnimation(.spring(response: 0.68, dampingFraction: 0.74)) {
            rewardCardScale = 1.06
            rewardCardOpacity = 1
            flashOpacity = 0
        }
        await openExit

        try? await Task.sleep(nanoseconds: 180_000_000)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            rewardCardScale = 1
        }

        guard stillCurrent() else {
            abortOpen(message: nil, generation: generation)
            return
        }

        LuckyBoxLocalStore.saveOpen(reward: picked)
        LuckyBoxQuotaState.shared.applyLocalOpened()
        todayDrops = LuckyBoxLocalStore.todayDrops
        galleryIndex = max(0, todayDrops.count - 1)
        hasOpenedToday = true
        phase = .revealed

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.35)) {
            revealOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        isBusy = false
    }

    @MainActor
    private func abortOpen(message: String?, generation: Int) {
        guard openGeneration == generation else { return }
        flashOpacity = 0
        rewardCardOpacity = 0
        rewardCardImage = nil
        isClickLocked = false
        chestController.scene.resetToClosed()
        phase = .readyToOpen
        isBusy = false
        if let message, !message.isEmpty {
            allowsLeavingAfterError = true
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
        resolvedImage ?? preloadedImage
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
        guard let url = reward?.resolvedImageURL else {
            resolvedImage = preloadedImage
            return
        }
        resolvedImage = CollectibleImageCache.shared.bestCachedImage(for: url) ?? preloadedImage
    }

    private func loadImageIfNeeded() async {
        guard let url = reward?.resolvedImageURL else { return }
        if CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: 1200) != nil {
            if resolvedImage == nil {
                resolvedImage = CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: 1200)
            }
            return
        }
        let image = await CollectibleImageCache.shared.image(for: url, maxPixelSize: 1200)
        guard !Task.isCancelled else { return }
        if let image {
            resolvedImage = image
            didFailLoading = false
        } else if displayImage == nil {
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

struct LuckyBoxAllowsLeavingKey: PreferenceKey {
    static var defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

private struct LuckyBoxSwipeBackLock: UIViewControllerRepresentable {
    var isLocked: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isLocked
        }
    }
}

// MARK: - Tomorrow chests info

private struct LuckyBoxTomorrowInfoSheet: View {
    @ObservedObject var quota: LuckyBoxQuotaState
    let gold: Color
    let orange: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Dnes služeb", systemImage: "bolt.fill")
                        Spacer()
                        Text("\(quota.servicesToday)")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                    HStack {
                        Label("Zítra bonusových beden", systemImage: "gift.fill")
                        Spacer()
                        Text("\(quota.tomorrowBonusCount)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(gold)
                            .monospacedDigit()
                    }
                    if let next = LuckyBoxQuota.nextBonus(services: quota.servicesToday) {
                        HStack {
                            Label("Další bonus", systemImage: "plus.circle")
                            Spacer()
                            Text("za \(next.need) \(LuckyBoxQuota.servicesWord(next.need))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Dnešní výkon se do Lucky Boxu započítá až zítra. Storno se nepočítá.")
                }

                Section {
                    thresholdRow(services: 2, bonus: 1, title: "Dvě služby")
                    thresholdRow(services: 3, bonus: 1, title: "Tři služby")
                    thresholdRow(services: 5, bonus: 2, title: "Dobrý den")
                    thresholdRow(services: 7, bonus: 3, title: "Silný den")
                } header: {
                    Text("Bonusové bedny")
                }

                Section {
                    luckRow(services: 4, percent: 12)
                    luckRow(services: 5, percent: 22, extra: "start na 2★")
                    luckRow(services: 7, percent: 35, extra: "start na 3★")
                } header: {
                    Text("Šance na drop")
                } footer: {
                    Text("Nejčastěji padne běžná karta. Včerejší služby zvedají šanci na vzácnější drop. Od 5 služeb start na 2★, od 7 na 3★.")
                }
            }
            .navigationTitle("Další bedny")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func thresholdRow(services: Int, bonus: Int, title: String) -> some View {
        let reached = quota.servicesToday >= services
        return HStack {
            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(reached ? Color(red: 0.35, green: 0.82, blue: 0.48) : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(services) \(LuckyBoxQuota.servicesWord(services))")
                    .font(.body.weight(.medium))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(bonus) \(LuckyBoxQuota.chestsWord(bonus))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reached ? gold : .secondary)
        }
    }

    private func luckRow(services: Int, percent: Int, extra: String? = nil) -> some View {
        HStack {
            Text("\(services)+ služeb")
            Spacer()
            Text(extra.map { "+\(percent) % · \($0)" } ?? "+\(percent) %")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Home entry helpers

enum LuckyBoxHomeStatus {
    case ready(remaining: Int, opened: Int)
    case waitingForBonus(hint: String)
    case doneForToday(countdown: String)

    @MainActor
    static func current(now: Date = Date()) -> LuckyBoxHomeStatus {
        let quota = LuckyBoxQuotaState.shared
        if quota.remaining > 0 {
            return .ready(remaining: quota.remaining, opened: quota.opened)
        }
        if let hint = quota.nextHint {
            return .waitingForBonus(hint: hint)
        }
        return .doneForToday(countdown: LuckyBoxLocalStore.countdownText(reference: now))
    }
}

#Preview {
    NavigationStack {
        LuckyBoxView()
    }
}
