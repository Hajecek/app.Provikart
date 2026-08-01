//
//  LuckyBoxView.swift
//  Provikart
//
//  Testovací denní Lucky Box – 4 pokusy o hvězdy, pak otevření (mock).
//

import SwiftUI

// MARK: - Model

enum LuckyBoxRarity: String, Codable, CaseIterable {
    case common
    case uncommon
    case rare
    case epic

    var title: String {
        switch self {
        case .common: return "Běžná"
        case .uncommon: return "Neobvyklá"
        case .rare: return "Vzácná"
        case .epic: return "Epická"
        }
    }

    var stars: Int {
        switch self {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 3
        case .epic: return 4
        }
    }

    static func from(stars: Int) -> LuckyBoxRarity {
        switch stars {
        case 1: return .common
        case 2: return .uncommon
        case 3: return .rare
        default: return .epic
        }
    }

    var tint: Color {
        switch self {
        case .common: return Color(red: 0.55, green: 0.78, blue: 1.0)
        case .uncommon: return Color(red: 0.45, green: 0.85, blue: 0.75)
        case .rare: return Color(red: 0.72, green: 0.55, blue: 1.0)
        case .epic: return Color(red: 1.0, green: 0.82, blue: 0.28)
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .common:
            return [
                Color(red: 0.10, green: 0.28, blue: 0.72),
                Color(red: 0.05, green: 0.14, blue: 0.42),
                Color(red: 0.02, green: 0.05, blue: 0.18)
            ]
        case .uncommon:
            return [
                Color(red: 0.08, green: 0.48, blue: 0.58),
                Color(red: 0.04, green: 0.24, blue: 0.40),
                Color(red: 0.02, green: 0.08, blue: 0.20)
            ]
        case .rare:
            return [
                Color(red: 0.42, green: 0.18, blue: 0.78),
                Color(red: 0.24, green: 0.08, blue: 0.48),
                Color(red: 0.08, green: 0.03, blue: 0.20)
            ]
        case .epic:
            return [
                Color(red: 0.72, green: 0.38, blue: 0.08),
                Color(red: 0.48, green: 0.14, blue: 0.28),
                Color(red: 0.16, green: 0.05, blue: 0.18)
            ]
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
        if h > 0 {
            return String(format: "%d h %02d min", h, m)
        }
        return String(format: "%d min", max(1, m))
    }
}

enum LuckyBoxMockPool {
    static let maxClicks = 4
    static let maxStars = 4

    /// Šance na +1 hvězdu při daném aktuálním počtu hvězd.
    static func upgradeChance(fromStars: Int) -> Double {
        switch fromStars {
        case 1: return 0.38
        case 2: return 0.24
        case 3: return 0.12
        default: return 0
        }
    }

    static let rewards: [LuckyBoxReward] = [
        LuckyBoxReward(id: "xp_small", title: "+5 XP", subtitle: "Malý bonus do Deal Wars", iconName: "bolt.fill", rarity: .common, weight: 40),
        LuckyBoxReward(id: "coffee", title: "Virtuální kafe", subtitle: "Protože si to zasloužíš", iconName: "cup.and.saucer.fill", rarity: .common, weight: 28),
        LuckyBoxReward(id: "luck", title: "Štěstí týmu", subtitle: "Dnes ti to bude sedět", iconName: "sparkles", rarity: .common, weight: 24),
        LuckyBoxReward(id: "xp_mid", title: "+12 XP", subtitle: "Příjemný denní přídavek", iconName: "bolt.circle.fill", rarity: .uncommon, weight: 30),
        LuckyBoxReward(id: "focus", title: "Focus mode", subtitle: "Kosmetický titul na den", iconName: "eye.fill", rarity: .uncommon, weight: 22),
        LuckyBoxReward(id: "xp_medium", title: "+15 XP", subtitle: "Solidní denní přídavek", iconName: "bolt.circle.fill", rarity: .rare, weight: 26),
        LuckyBoxReward(id: "streak", title: "Streak shield", subtitle: "Ochrana denní série (mock)", iconName: "shield.fill", rarity: .rare, weight: 18),
        LuckyBoxReward(id: "xp_big", title: "+40 XP", subtitle: "Velký skok v žebříčku", iconName: "flame.fill", rarity: .epic, weight: 20),
        LuckyBoxReward(id: "crown", title: "Korunka dne", subtitle: "Epický flair do profilu", iconName: "crown.fill", rarity: .epic, weight: 14)
    ]

    static func pickReward(for rarity: LuckyBoxRarity) -> LuckyBoxReward {
        let pool = rewards.filter { $0.rarity == rarity }
        let source = pool.isEmpty ? rewards : pool
        let total = source.reduce(0) { $0 + max(1, $1.weight) }
        var roll = Int.random(in: 0..<max(1, total))
        for reward in source {
            roll -= max(1, reward.weight)
            if roll < 0 { return reward }
        }
        return source[0]
    }
}

// MARK: - View

struct LuckyBoxView: View {
    @State private var phase: LuckyBoxPhase = .charging
    @State private var stars: Int = 1
    @State private var clicksLeft: Int = LuckyBoxMockPool.maxClicks
    @State private var reward: LuckyBoxReward?
    @State private var hasOpenedToday = LuckyBoxLocalStore.hasOpenedToday
    @State private var boxScale: CGFloat = 1
    @State private var boxRotation: Double = 0
    @State private var boxBounce: CGFloat = 0
    @State private var lidOpen: CGFloat = 0
    @State private var glowPulse = false
    @State private var hintPulse = false
    @State private var revealOpacity: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var starBurst = false
    @State private var particleBoost = false
    @State private var isBusy = false
    @State private var countdownTick = Date()
    @State private var hitAnimationTask: Task<Void, Never>?
    @State private var pendingHitShakes: [Bool] = []
    @State private var shakeParticles: [LuckyShakeParticle] = []

    private let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
    private let orange = Color(red: 0.97, green: 0.58, blue: 0.12)

    private var currentRarity: LuckyBoxRarity {
        .from(stars: stars)
    }

    var body: some View {
        ZStack {
            fullscreenBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.55), value: stars)

            particlesLayer
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                starsRow
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                Spacer(minLength: 8)

                chestView
                    .padding(.horizontal, 24)

                Spacer(minLength: 16)

                bottomSection
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // flash musí být navrchu – zakryje bednu i UI
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await handleTap() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    resetForTesting()
                }
                .accessibilityLabel("Resetovat dnešní Lucky Box")
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            glowPulse = true
            hintPulse = true
            if hasOpenedToday, let last = LuckyBoxLocalStore.lastReward {
                reward = last
                stars = last.rarity.stars
                clicksLeft = 0
                phase = .revealed
                revealOpacity = 1
                lidOpen = 1
            }
        }
        .task {
            while !Task.isCancelled {
                countdownTick = Date()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private var fullscreenBackground: some View {
        let colors = currentRarity.backgroundColors
        let tint = currentRarity.tint
        return ZStack {
            LinearGradient(
                colors: [colors[0], colors[1], colors[2], .black],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.white.opacity(0.18), tint.opacity(0.12), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 10,
                endRadius: 320
            )

            RadialGradient(
                colors: [tint.opacity(glowPulse ? 0.35 : 0.18), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 20,
                endRadius: 220
            )
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowPulse)

            // měkká podlaha – bez zubatých diamantů
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35), Color.black.opacity(0.7)],
                startPoint: UnitPoint(x: 0.5, y: 0.55),
                endPoint: .bottom
            )

            LuckySoftFloor(accent: tint)
                .opacity(0.55)
                .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.55)],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 130,
                endRadius: 520
            )
        }
    }

    private var particlesLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = particleBoost ? 42 : 28
                for i in 0..<count {
                    let seed = Double(i) * 17.13 + 3.7
                    let dirX = sin(seed * 1.9)
                    let dirY = cos(seed * 2.3)
                    let speed = 0.22 + Double(i % 7) * 0.05
                    let baseX = (sin(seed) * 0.5 + 0.5) * size.width
                    let baseY = (cos(seed * 1.4) * 0.5 + 0.5) * size.height * 0.85
                    let x = baseX + dirX * sin(t * speed + seed) * (18 + Double(i % 5) * 6)
                    let y = baseY + dirY * cos(t * speed * 0.9 + seed * 1.1) * (14 + Double(i % 4) * 5)
                        - (t * (8 + Double(i % 6) * 3) + seed * 20)
                            .truncatingRemainder(dividingBy: Double(size.height * 0.55))
                    let r = 1.2 + CGFloat(i % 5) * 0.7
                    let warm = i % 3 == 0
                    var path = Path()
                    path.addEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                    context.fill(
                        path,
                        with: .color(
                            (warm ? Color(red: 1, green: 0.86, blue: 0.45) : .white)
                                .opacity(0.18 + 0.28 * Double((i % 4) + 1) / 4.0)
                        )
                    )
                }
            }
        }
        .opacity(phase == .revealed ? 0.3 : 0.7)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var starsRow: some View {
        HStack(spacing: 12) {
            ForEach(1...LuckyBoxMockPool.maxStars, id: \.self) { index in
                LuckyStarBadge(
                    filled: index <= stars,
                    emphasized: starBurst && index == stars,
                    gold: gold,
                    orange: orange
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
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        )
        .accessibilityLabel("\(stars) z \(LuckyBoxMockPool.maxStars) hvězd")
    }

    private var chestView: some View {
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

            LuckyChestRig(lidOpen: lidOpen, rarityTint: currentRarity.tint, gold: gold)
                .frame(width: 290, height: 290)
                .scaleEffect(boxScale)
                .rotationEffect(.degrees(boxRotation))
                .offset(y: boxBounce)
                .shadow(color: currentRarity.tint.opacity(0.35 + 0.25 * lidOpen), radius: 26, y: 12)

            // partikly NAVRCHU bedny, jinak je truhla překryje
            LuckyShakeParticleLayer(particles: shakeParticles)
                .frame(width: 380, height: 380)
                .allowsHitTesting(false)
        }
        .frame(height: 360)
    }

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 18) {
            if phase == .revealed, let reward {
                Text(reward.rarity.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(reward.rarity.tint)

                Text(reward.title)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(revealOpacity)

                Text(reward.subtitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .opacity(revealOpacity)

                Text("Další za \(LuckyBoxLocalStore.countdownText(reference: countdownTick))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gold.opacity(0.9))
                    .monospacedDigit()
                    .opacity(revealOpacity)
            } else if hasOpenedToday && phase != .opening {
                Text("Dnes už otevřeno")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Vrať se zítra · \(LuckyBoxLocalStore.countdownText(reference: countdownTick))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
            } else {
                clickTokensRow

                Text(hintText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(hintPulse ? 1 : 0.55))
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: hintPulse)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 130, alignment: .top)
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
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: clicksLeft)
            }
        }
        .accessibilityLabel("Zbývá \(clicksLeft) pokusů")
    }

    private func resetForTesting() {
        LuckyBoxLocalStore.resetToday()
        hasOpenedToday = false
        reward = nil
        stars = 1
        clicksLeft = LuckyBoxMockPool.maxClicks
        phase = .charging
        revealOpacity = 0
        lidOpen = 0
        boxScale = 1
        boxRotation = 0
        boxBounce = 0
        flashOpacity = 0
        isBusy = false
        pendingHitShakes.removeAll()
        shakeParticles.removeAll()
        hitAnimationTask?.cancel()
        hitAnimationTask = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor
    private func handleTap() async {
        if hasOpenedToday && phase == .revealed { return }

        switch phase {
        case .charging:
            performUpgradeAttempt()
        case .readyToOpen:
            guard !isBusy else { return }
            await openChest()
        case .opening, .revealed:
            break
        }
    }

    @MainActor
    private func performUpgradeAttempt() {
        guard phase == .charging, clicksLeft > 0 else {
            if clicksLeft == 0, phase == .charging {
                phase = .readyToOpen
            }
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            clicksLeft -= 1
        }

        let chance = LuckyBoxMockPool.upgradeChance(fromStars: stars)
        let upgraded = stars < LuckyBoxMockPool.maxStars && Double.random(in: 0...1) < chance

        if upgraded {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                stars += 1
                starBurst = true
            }
            flashOpacity = 0.35
            withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }

        // fronta plynulých shake animací – klepnutí jde hned, shake doběhne jeden po druhém
        pendingHitShakes.append(upgraded)
        startHitAnimationQueueIfNeeded()

        if clicksLeft == 0 {
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = .readyToOpen
            }
        }
    }

    @MainActor
    private func startHitAnimationQueueIfNeeded() {
        guard hitAnimationTask == nil else { return }

        hitAnimationTask = Task { @MainActor in
            while !pendingHitShakes.isEmpty {
                guard !Task.isCancelled else { break }
                let upgraded = pendingHitShakes.removeFirst()
                await playOneHitShake(upgraded: upgraded)
            }
            hitAnimationTask = nil
        }
    }

    @MainActor
    private func playOneHitShake(upgraded: Bool) async {
        // přirozené třesení – amplituda postupně doznívá
        let steps = 7
        for i in 0..<steps {
            guard !Task.isCancelled else { return }
            let progress = Double(i) / Double(steps - 1)
            let decay = 1 - progress
            let sign: Double = i.isMultiple(of: 2) ? 1 : -1
            let wobble = 1 + 0.12 * sin(Double(i) * 2.1)
            let amp = 11 * decay * wobble

            withAnimation(.interpolatingSpring(stiffness: 420, damping: 18)) {
                boxRotation = sign * amp
                boxScale = 1 + 0.045 * decay * (i.isMultiple(of: 2) ? 1 : -0.7)
                boxBounce = -amp * 0.7 + (i.isMultiple(of: 2) ? 0 : 5 * decay)
            }
            try? await Task.sleep(nanoseconds: UInt64(62_000_000 + progress * 18_000_000))
        }

        guard !Task.isCancelled else { return }

        if upgraded {
            emitStarUpgradeParticles()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
                boxScale = 1.14
                boxRotation = 0
                boxBounce = -14
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                boxScale = 1
                boxBounce = 0
                starBurst = false
            }
            try? await Task.sleep(nanoseconds: 160_000_000)
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                boxRotation = 0
                boxScale = 1
                boxBounce = 8
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
                boxBounce = 0
            }
            try? await Task.sleep(nanoseconds: 70_000_000)
        }
    }

    @MainActor
    private func emitStarUpgradeParticles() {
        let now = Date()
        let assets = ["LuckyParticleGold", "LuckyParticleCyan", "LuckyParticleSoft"]
        let count = 6
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .pi * 2 + Double.random(in: -0.15...0.15)
            shakeParticles.append(
                LuckyShakeParticle(
                    assetName: assets[i % assets.count],
                    angle: angle,
                    startRadius: Double.random(in: 88...108),
                    speed: Double.random(in: 35...70),
                    size: CGFloat.random(in: 24...36),
                    spin: Double.random(in: -60...60),
                    startedAt: now,
                    duration: Double.random(in: 0.55...0.75)
                )
            )
        }
        if shakeParticles.count > 18 {
            shakeParticles.removeFirst(shakeParticles.count - 18)
        }
    }

    @MainActor
    private func openChest() async {
        isBusy = true
        phase = .opening
        revealOpacity = 0
        pendingHitShakes.removeAll()
        shakeParticles.removeAll()
        hitAnimationTask?.cancel()
        hitAnimationTask = nil
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // před-open shake (zavřená bedna)
        for i in 0..<8 {
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

        // full-screen flash – zakryje obrazovku ještě před otevřením
        withAnimation(.easeIn(duration: 0.12)) {
            flashOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 130_000_000)

        // za bílým flashem už je bedna otevřená
        lidOpen = 1
        boxScale = 1.12
        boxBounce = -8
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        // krátký „hold“ na plném flashi
        try? await Task.sleep(nanoseconds: 160_000_000)

        // flash mizí → odhalí otevřenou bednu
        withAnimation(.easeOut(duration: 0.55)) {
            flashOpacity = 0
            boxScale = 1.04
            boxBounce = -4
        }
        try? await Task.sleep(nanoseconds: 480_000_000)

        let rarity = LuckyBoxRarity.from(stars: stars)
        let picked = LuckyBoxMockPool.pickReward(for: rarity)
        LuckyBoxLocalStore.saveOpen(reward: picked)
        reward = picked
        hasOpenedToday = true
        phase = .revealed

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            boxScale = 1
            boxBounce = 0
            revealOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        particleBoost = false
        isBusy = false
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

// MARK: - Chest (closed → open crossfade)

private struct LuckyChestRig: View {
    let lidOpen: CGFloat
    let rarityTint: Color
    let gold: Color

    var body: some View {
        ZStack {
            // vnitřní glow při otevření
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.7 * lidOpen),
                            gold.opacity(0.55 * lidOpen),
                            rarityTint.opacity(0.2 * lidOpen),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 110
                    )
                )
                .frame(width: 200, height: 200)
                .offset(y: -10)
                .blur(radius: 4)
                .blendMode(.plusLighter)

            Image("LuckyChestClosed")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .opacity(Double(1 - lidOpen))
                .scaleEffect(1 - lidOpen * 0.04)

            Image("LuckyChestOpen")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .opacity(Double(lidOpen))
                .scaleEffect(0.92 + lidOpen * 0.08)
        }
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

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let horizon = size.height * 0.58
                for i in 0..<10 {
                    let t = CGFloat(i) / 9
                    let y = horizon + pow(t, 1.6) * (size.height - horizon)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(accent.opacity(0.05 + 0.1 * t)), lineWidth: 1)
                }
                for i in 0...10 {
                    let u = CGFloat(i) / 10
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * (0.5 + (u - 0.5) * 0.22), y: horizon))
                    path.addLine(to: CGPoint(x: size.width * (0.5 + (u - 0.5) * 1.25), y: size.height))
                    context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
                }
            }
            .mask(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5), .black],
                    startPoint: UnitPoint(x: 0.5, y: 0.52),
                    endPoint: .bottom
                )
            )
        }
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
