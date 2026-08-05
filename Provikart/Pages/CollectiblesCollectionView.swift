//
//  CollectiblesCollectionView.swift
//  Provikart
//
//  Sbírka předmětů – inventář z collectibles.php.
//

import ImageIO
import SwiftUI
import UIKit

private enum CollectiblesOwnershipFilter: String, CaseIterable, Identifiable {
    case all
    case owned
    case locked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Vše"
        case .owned: return "Vlastněné"
        case .locked: return "Zamčené"
        }
    }
}

private enum CollectiblesRarityFilter: String, CaseIterable, Identifiable {
    case all
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Vše"
        case .common: return LuckyBoxRarity.common.title
        case .uncommon: return LuckyBoxRarity.uncommon.title
        case .rare: return LuckyBoxRarity.rare.title
        case .epic: return LuckyBoxRarity.epic.title
        case .legendary: return LuckyBoxRarity.legendary.title
        }
    }

    var rarity: LuckyBoxRarity? {
        switch self {
        case .all: return nil
        case .common: return .common
        case .uncommon: return .uncommon
        case .rare: return .rare
        case .epic: return .epic
        case .legendary: return .legendary
        }
    }

    var tint: Color {
        rarity?.tint ?? Color(red: 1.0, green: 0.86, blue: 0.42)
    }
}

struct CollectiblesCollectionView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var inventory: CollectiblesInventory?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: CollectibleItem?
    @State private var ownershipFilter: CollectiblesOwnershipFilter = .all
    @State private var rarityFilter: CollectiblesRarityFilter = .all
    @State private var showProgressDetail = false
    /// Po refreshi vynutí znovunačtení thumbnailů (stejná URL ≠ stejný obsah).
    @State private var imageEpoch = 0

    private let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
    private let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredItems: [CollectibleItem] {
        let items = inventory?.items ?? []
        return items.filter { item in
            switch ownershipFilter {
            case .all: break
            case .owned: if !item.owned { return false }
            case .locked: if item.owned { return false }
            }
            if let rarity = rarityFilter.rarity {
                if LuckyBoxRarity.from(api: item.rarity) != rarity { return false }
            }
            return true
        }
        .sorted { lhs, rhs in
            if lhs.owned != rhs.owned { return lhs.owned && !rhs.owned }
            let lR = LuckyBoxRarity.from(api: lhs.rarity).stars
            let rR = LuckyBoxRarity.from(api: rhs.rarity).stars
            if lR != rR { return lR > rR }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if isLoading && inventory == nil {
                ProgressView("Načítám sbírku…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, inventory == nil {
                ContentUnavailableView {
                    Label("Sbírku se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Zkusit znovu") {
                        Task { await loadInventory(forceImageRefresh: true) }
                    }
                }
            } else {
                collectionContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Sbírka")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let inventory {
                ToolbarItem(placement: .topBarTrailing) {
                    CollectiblesToolbarStats(
                        wallet: inventory.wallet,
                        currencyName: inventory.currency.name,
                        owned: inventory.ownedCount,
                        total: inventory.total,
                        gold: gold,
                        orange: orange
                    ) {
                        showProgressDetail = true
                    }
                }
            }
        }
        .sheet(isPresented: $showProgressDetail) {
            if let inventory {
                NavigationStack {
                    CollectiblesProgressDetailView(inventory: inventory, gold: gold, orange: orange)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Hotovo") { showProgressDetail = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            await loadInventory()
        }
        .refreshable {
            await loadInventory(forceImageRefresh: true)
        }
        .sheet(item: $selectedItem) { item in
            CollectibleDetailSheet(
                item: item,
                wallet: inventory?.wallet ?? 0,
                currency: inventory?.currency ?? CollectiblesCurrency(),
                gold: gold,
                orange: orange
            ) { updated in
                inventory = updated
            }
            .environmentObject(authState)
        }
    }

    private var collectionContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                filtersSection

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "Nic nenalezeno",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Zkus změnit filtr vlastnictví nebo rarity.")
                    )
                    .frame(minHeight: 220)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                CollectibleGridCell(item: item, imageEpoch: imageEpoch)
                                    .equatable()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .padding(.top, 4)
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Stav", selection: $ownershipFilter) {
                ForEach(CollectiblesOwnershipFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CollectiblesRarityFilter.allCases) { filter in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                rarityFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if let rarity = filter.rarity {
                                    Circle()
                                        .fill(rarity.tint)
                                        .frame(width: 8, height: 8)
                                }
                                Text(filter.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(rarityFilter == filter ? Color.white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        rarityFilter == filter
                                            ? filter.tint.opacity(filter.rarity == nil ? 0.85 : 0.95)
                                            : Color(uiColor: .secondarySystemGroupedBackground)
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        rarityFilter == filter
                                            ? filter.tint.opacity(0.25)
                                            : Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            Text(filterSummaryText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    private var filterSummaryText: String {
        let count = filteredItems.count
        let total = inventory?.items.count ?? 0
        if ownershipFilter == .all, rarityFilter == .all {
            return "Zobrazeno \(count) z \(total)"
        }
        return "Filtrováno \(count) z \(total)"
    }

    @MainActor
    private func loadInventory(forceImageRefresh: Bool = false) async {
        if inventory == nil { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fresh = try await CollectiblesService().fetchInventory(token: authState.authToken)
            inventory = fresh
            if forceImageRefresh {
                CollectibleImageCache.shared.clearMemory()
                imageEpoch &+= 1
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Toolbar badges + progress sheet

private struct CollectiblesToolbarStats: View {
    let wallet: Int
    let currencyName: String
    let owned: Int
    let total: Int
    let gold: Color
    let orange: Color
    let onProgressTap: () -> Void

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(owned) / Double(total))
    }

    var body: some View {
        HStack(spacing: 0) {
            powderSegment
            segmentDivider
            progressSegment
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(chromeBackground)
        .accessibilityElement(children: .contain)
    }

    private var powderSegment: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0.95), orange.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .shadow(color: orange.opacity(0.35), radius: 3, y: 1)

                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Prach")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(wallet)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(currencyName), \(wallet)")
    }

    private var progressSegment: some View {
        Button(action: onProgressTap) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [gold, orange, gold], center: .center),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(orange.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Sbírka")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Text("\(owned)")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                        Text("/\(total)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pokrok sbírky, \(owned) z \(total)")
        .accessibilityHint("Zobrazí detail pokroku")
    }

    private var segmentDivider: some View {
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
    }

    private var chromeBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                gold.opacity(0.45),
                                Color.primary.opacity(0.08),
                                orange.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 1)
    }
}

private struct CollectiblesProgressDetailView: View {
    let inventory: CollectiblesInventory
    let gold: Color
    let orange: Color

    private var progress: Double {
        guard inventory.total > 0 else { return 0 }
        return min(1, Double(inventory.ownedCount) / Double(inventory.total))
    }

    private var remaining: Int {
        max(0, inventory.total - inventory.ownedCount)
    }

    private var percent: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 14)
                        .frame(width: 128, height: 128)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [gold, orange, gold], center: .center),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 128, height: 128)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: orange.opacity(0.35), radius: 8, y: 2)

                    VStack(spacing: 2) {
                        Text("\(percent)")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)

                Text("Pokrok sbírky")
                    .font(.title3.weight(.bold))

                Text("\(inventory.ownedCount) z \(inventory.total) předmětů")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                HStack(spacing: 10) {
                    progressStatPill(
                        value: "\(inventory.ownedCount)",
                        label: "vlastněno",
                        tint: Color(red: 0.35, green: 0.78, blue: 0.55)
                    )
                    progressStatPill(
                        value: "\(remaining)",
                        label: "zbývá",
                        tint: Color(red: 0.95, green: 0.55, blue: 0.35)
                    )
                }
                .padding(.horizontal, 20)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [gold, orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Pokrok")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func progressStatPill(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

// MARK: - Grid cell

private struct CollectibleGridCell: View, Equatable {
    let item: CollectibleItem
    var imageEpoch: Int = 0

    static func == (lhs: CollectibleGridCell, rhs: CollectibleGridCell) -> Bool {
        lhs.item == rhs.item && lhs.imageEpoch == rhs.imageEpoch
    }

    private var rarity: LuckyBoxRarity {
        LuckyBoxRarity.from(api: item.rarity)
    }

    private var gold: Color { Color(red: 1.0, green: 0.86, blue: 0.42) }

    var body: some View {
        VStack(spacing: 8) {
            cardFace

            VStack(spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item.owned ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)

                Text(rarity.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.owned ? rarity.tint : Color.secondary)

                if !item.owned {
                    Text(item.canCraft ? "Připraveno k craftu" : "Zbývá \(item.remainingToCraft) prachu")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(item.canCraft ? gold : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var cardFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.owned
                            ? rarity.backgroundColors
                            : [
                                Color(uiColor: .tertiarySystemFill),
                                Color(uiColor: .quaternarySystemFill)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            CollectibleCachedThumbnail(
                url: item.resolvedImageURL,
                owned: item.owned,
                epoch: imageEpoch
            )
            .padding(14)

            if !item.owned {
                Color.black.opacity(0.28)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Image(systemName: "lock.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }

            if item.owned, item.qty > 1 {
                Text("×\(item.qty)")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
        }
        .aspectRatio(0.85, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    item.owned ? rarity.tint.opacity(0.45) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Cached thumbnail

private struct CollectibleCachedThumbnail: View {
    let url: URL?
    var owned: Bool = true
    var epoch: Int = 0

    @State private var image: UIImage?
    @State private var didFail = false

    private let displaySize: CGFloat = 140
    private var maxPixelSize: CGFloat {
        displaySize * UIScreen.main.scale
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .opacity(owned ? 1 : 0.55)
            } else if didFail || url == nil {
                questionMarkPlaceholder
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(url?.absoluteString ?? "")#\(epoch)") {
            await load()
        }
    }

    private var questionMarkPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(owned ? 0.18 : 0.28))
                .frame(width: 72, height: 72)

            Image(systemName: "questionmark")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(owned ? 0.92 : 0.7))
        }
    }

    private func load() async {
        guard let url else {
            didFail = true
            return
        }
        if let cached = CollectibleImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
            image = cached
            didFail = false
            return
        }
        // Po invalidaci cache nech starý bitmap nezůstávat na obrazovce.
        if image != nil {
            image = nil
        }
        didFail = false
        let loaded = await CollectibleImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled else { return }
        if let loaded {
            image = loaded
            didFail = false
        } else {
            didFail = true
        }
    }
}

// MARK: - Detail + powder actions

struct CollectibleDetailSheet: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var item: CollectibleItem
    @State private var wallet: Int
    let currency: CollectiblesCurrency
    let gold: Color
    let orange: Color
    let onUpdated: (CollectiblesInventory) -> Void

    @State private var isBusy = false
    @State private var actionError: String?

    init(
        item: CollectibleItem,
        wallet: Int,
        currency: CollectiblesCurrency,
        gold: Color,
        orange: Color,
        onUpdated: @escaping (CollectiblesInventory) -> Void
    ) {
        _item = State(initialValue: item)
        _wallet = State(initialValue: wallet)
        self.currency = currency
        self.gold = gold
        self.orange = orange
        self.onUpdated = onUpdated
    }

    private var reward: LuckyBoxReward {
        LuckyBoxReward(from: item, currency: currency)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LuckyRewardCardView(reward: reward, gold: gold, isInteractive: true)
                        .frame(maxWidth: 320)
                        .frame(height: 430)
                        .padding(.top, 8)

                    if !item.owned {
                        powderPanel
                    }

                    infoRows

                    if let description = item.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Popis")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(description)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Akce selhala", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .disabled(isBusy)
            .overlay {
                if isBusy {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView()
                            .padding(18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var powderPanel: some View {
        let need = max(item.remainingToCraft, 0)
        let allocated = max(item.allocatedPowder, 0)
        let craftTotal = max(need + allocated, need, 1)
        let craftProgress = item.canCraft ? 1.0 : min(1, Double(allocated) / Double(craftTotal))

        return VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [gold, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(red: 0.25, green: 0.1, blue: 0.03))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hvězdný prach")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("Zásoba \(wallet)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.canCraft ? "Připraveno k craftu" : "Do odemčení")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if item.canCraft {
                        Text("0 zbývá")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.55))
                    } else {
                        Text("\(need)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        + Text(" prachu")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: item.canCraft
                                        ? [Color(red: 0.35, green: 0.78, blue: 0.55), Color(red: 0.2, green: 0.65, blue: 0.45)]
                                        : [gold, orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * craftProgress))
                    }
                }
                .frame(height: 10)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )

            HStack(spacing: 12) {
                powderControlButton(
                    title: "Odebrat",
                    subtitle: "−1",
                    systemImage: "minus.circle.fill",
                    tint: Color(red: 0.95, green: 0.45, blue: 0.4),
                    enabled: !isBusy && canRecall(1)
                ) {
                    await runAction("recall", amount: 1)
                }

                powderControlButton(
                    title: "Přidat",
                    subtitle: "+1",
                    systemImage: "plus.circle.fill",
                    tint: gold,
                    enabled: !isBusy && canAllocate(1)
                ) {
                    await runAction("allocate", amount: 1)
                }

                powderControlButton(
                    title: "Přidat",
                    subtitle: "+5",
                    systemImage: "plus.circle.fill",
                    tint: orange,
                    enabled: !isBusy && canAllocate(5)
                ) {
                    await runAction("allocate", amount: 5)
                }
            }

            if item.canCraft {
                Button {
                    Task { await runAction("craft", amount: 0) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "hammer.fill")
                        Text("Craftnout předmět")
                            .fontWeight(.bold)
                    }
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.22, green: 0.1, blue: 0.03))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [gold, orange], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: orange.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [gold.opacity(0.4), orange.opacity(0.12), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }

    private func powderControlButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        enabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.35))
                Text(subtitle)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(enabled ? .primary : .secondary)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(enabled ? 0.14 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(enabled ? 0.28 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var infoRows: some View {
        VStack(spacing: 0) {
            detailRow(icon: "seal.fill", title: "Rarita", value: reward.rarity.title, tint: reward.rarity.tint)
            Divider().padding(.leading, 52)
            detailRow(
                icon: item.owned ? "checkmark.circle.fill" : "lock.fill",
                title: "Stav",
                value: item.owned ? "Ve sbírce ×\(max(1, item.qty))" : "Nezískáno",
                tint: item.owned ? Color(red: 0.35, green: 0.78, blue: 0.55) : .secondary
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
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
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func canAllocate(_ amount: Int) -> Bool {
        wallet >= amount
    }

    private func canRecall(_ amount: Int) -> Bool {
        if item.allocatedPowder > 0 {
            return item.allocatedPowder >= amount
        }
        return true
    }

    @MainActor
    private func runAction(_ action: String, amount: Int) async {
        isBusy = true
        actionError = nil
        defer { isBusy = false }

        do {
            let updated = try await CollectiblesService().performAction(
                token: authState.authToken,
                action: action,
                collectibleId: item.id,
                amount: amount
            )
            wallet = updated.wallet
            if let fresh = updated.items.first(where: { $0.id == item.id }) {
                item = fresh
            }
            onUpdated(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
