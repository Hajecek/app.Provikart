//
//  OrdersView.swift
//  Provikart
//
//  Seznam objednávek a položek objednávek z API user_orders.
//

import SwiftUI

private func parseInstallationDate(_ raw: String?) -> Date? {
    guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    let ddMMyyyy: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "cs_CZ")
        return f
    }()
    let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    return ddMMyyyy.date(from: raw) ?? yyyyMMdd.date(from: raw)
}

private func formatOrderDate(_ raw: String?) -> String {
    guard let raw = raw, !raw.isEmpty else { return "—" }
    if let date = parseInstallationDate(raw) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "cs_CZ")
        return f.string(from: date)
    }
    return raw
}

private enum OrdersViewFormatting {
    static func price(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CZK"
        formatter.currencySymbol = "Kč"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value)) Kč"
    }
}

private let ordersLogoOrange = Color(red: 0.97, green: 0.58, blue: 0.12)
private let ordersLogoGold = Color(red: 0.98, green: 0.69, blue: 0.23)

// MARK: - Badge stavu objednávky / položky

private struct OrderStatusBadge: View {
    let status: String

    private var isPending: Bool { status.lowercased() == "pending" }
    private var isCompleted: Bool { status.lowercased() == "completed" }

    var body: some View {
        if isPending {
            HStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.caption.weight(.bold))
                Text("Čeká")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Color(red: 0.45, green: 0.28, blue: 0.02))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(ordersLogoGold.opacity(0.42))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(ordersLogoOrange.opacity(0.45), lineWidth: 1)
            }
        } else if isCompleted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                Text("Hotovo")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.14), in: Capsule())
        } else if !status.isEmpty {
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: Capsule())
        } else {
            EmptyView()
        }
    }
}

// MARK: - Hlavní view

private enum OrdersFilter: String, CaseIterable, Identifiable {
    case all = "Vše"
    case pending = "Čeká"
    case completed = "Hotovo"

    var id: String { rawValue }
}

struct OrdersView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet

    @State private var orders: [UserOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedOrderId: Int?
    @State private var selectedItemContext: OrderItemContext?
    @State private var selectedFilter: OrdersFilter = .all
    @State private var lastUpdatedAt: Date?
    private let service = UserOrdersService()

    private var pendingCount: Int {
        orders.filter { $0.effectiveStatus == "pending" }.count
    }

    private var completedCount: Int {
        orders.filter { $0.effectiveStatus == "completed" }.count
    }

    /// Součet provizí jen z dokončených položek (ne order.amount, ne pending).
    private var totalCommission: Double {
        orders.map(\.completedCommission).reduce(0, +)
    }

    private var filteredOrders: [UserOrder] {
        switch selectedFilter {
        case .all:
            return orders
        case .pending:
            return orders.filter { $0.effectiveStatus == "pending" }
        case .completed:
            return orders.filter { $0.effectiveStatus == "completed" }
        }
    }

    private var ordersRealtimeKey: String {
        orders.map(\.realtimeSignature).joined(separator: ";")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && orders.isEmpty {
                    loadingView
                } else if let msg = errorMessage, orders.isEmpty {
                    errorView(msg)
                } else if orders.isEmpty {
                    emptyView
                } else {
                    mainContent
                }
            }
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                    OrdersTopArchGlow()
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Objednávky")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        StatisticsView()
                            .environmentObject(authState)
                            .environment(\.openAddSheet, openAddSheet)
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                    NavigationLink {
                        UserAttendanceView()
                            .environmentObject(authState)
                    } label: {
                        Image(systemName: "person.badge.clock")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        DealwarsView()
                    } label: {
                        Image(systemName: "trophy")
                    }
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(item: $selectedOrderId) { orderId in
                if let order = orders.first(where: { $0.id == orderId }) {
                    OrderDetailView(
                        order: order,
                        selectedItemContext: $selectedItemContext,
                        onOrdersDidUpdate: { Task { await loadOrders(silent: false) } }
                    )
                }
            }
        }
        .sheet(item: $selectedItemContext) { ctx in
            let liveItem = orders
                .first(where: { $0.id == ctx.order.id })?
                .items.first(where: { $0.id == ctx.item.id }) ?? ctx.item
            UserOrderItemDetailSheet(
                orderNumber: orders.first(where: { $0.id == ctx.order.id })?.displayOrderNumber ?? ctx.order.displayOrderNumber,
                item: liveItem
            )
            .id("\(liveItem.id)-\(liveItem.statusDisplay)-\(liveItem.installation_day ?? "")-\(liveItem.installation_time ?? "")")
        }
        .task {
            await loadOrders(silent: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                await loadOrders(silent: true)
            }
        }
        .refreshable {
            await loadOrders(silent: false)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Načítám objednávky…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst objednávky", systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg)
        } actions: {
            Button("Zkusit znovu") { Task { await loadOrders(silent: false) } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Žádné objednávky", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Zatím nemáte žádné objednávky.")
        } actions: {
            if openAddSheet != nil {
                Button("Přidat položku") { openAddSheet?() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        List {
            Section {
                statsStrip
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                filterChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                if filteredOrders.isEmpty {
                    ContentUnavailableView(
                        "Nic v tomto filtru",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Zkuste jiný filtr nebo počkejte na nové objednávky.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredOrders, id: \.id) { order in
                        Button {
                            selectedOrderId = order.id
                        } label: {
                            OrderRow(order: order)
                        }
                        .buttonStyle(.plain)
                        .id(order.realtimeSignature)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            } header: {
                HStack {
                    Text(selectedFilter == .all ? "Všechny objednávky" : selectedFilter.rawValue)
                        .textCase(nil)
                    Spacer()
                    if let lastUpdatedAt {
                        Text(Self.relativeTimeFormatter.localizedString(for: lastUpdatedAt, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.snappy(duration: 0.22), value: selectedFilter)
        .animation(.snappy(duration: 0.25), value: ordersRealtimeKey)
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(title: "Celkem", value: "\(orders.count)", tint: ordersLogoOrange)
            Divider().frame(height: 28)
            statCell(title: "Čeká", value: "\(pendingCount)", tint: ordersLogoGold)
            Divider().frame(height: 28)
            statCell(title: "Hotovo", value: "\(completedCount)", tint: .green)
            Divider().frame(height: 28)
            statCell(title: "Provize", value: OrdersViewFormatting.price(totalCommission), tint: ordersLogoOrange)
        }
        .padding(.vertical, 12)
        .background(ordersCardBackground(tint: ordersLogoOrange))
    }

    private func statCell(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var filterChips: some View {
        Picker("Filtr", selection: $selectedFilter) {
            ForEach(OrdersFilter.allCases) { filter in
                Text(filterLabel(filter)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }

    private func filterLabel(_ filter: OrdersFilter) -> String {
        let count: Int = {
            switch filter {
            case .all: return orders.count
            case .pending: return pendingCount
            case .completed: return completedCount
            }
        }()
        return "\(filter.rawValue) \(count)"
    }

    private func loadOrders(silent: Bool) async {
        guard authState.authToken != nil else {
            await MainActor.run { errorMessage = "Pro zobrazení objednávek se přihlaste." }
            return
        }
        await MainActor.run {
            if !silent {
                isLoading = true
                if orders.isEmpty { errorMessage = nil }
            }
        }
        do {
            let fetched = try await service.fetchOrders(token: authState.authToken)
            await MainActor.run {
                withAnimation(.snappy(duration: 0.22)) {
                    orders = fetched
                }
                isLoading = false
                errorMessage = nil
                lastUpdatedAt = Date()
                if let selectedOrderId,
                   !fetched.contains(where: { $0.id == selectedOrderId }) {
                    self.selectedOrderId = nil
                }
            }
        } catch {
            if error is CancellationError { return }
            if let url = error as? URLError, url.code == .cancelled { return }
            await MainActor.run {
                isLoading = false
                if !silent, orders.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Řádek objednávky

private struct OrderRow: View {
    let order: UserOrder

    private var isCompleted: Bool {
        order.effectiveStatus == "completed"
    }

    private var isPending: Bool {
        order.effectiveStatus == "pending"
    }

    private var completedItemsCount: Int {
        order.items.filter { $0.statusDisplay.lowercased() == "completed" }.count
    }

    /// Provize jen z dokončených položek (ne order.amount).
    private var itemsCommission: Double {
        order.completedCommission
    }

    private var itemsLabel: String {
        let total = order.items.count
        if total == 0 { return "0 položek" }
        if completedItemsCount == total { return "\(total) hotovo" }
        if completedItemsCount == 0 { return "\(total) pol." }
        return "\(completedItemsCount)/\(total) hotovo"
    }

    private var badgeStatus: String {
        if order.items.isEmpty { return order.statusDisplay }
        return order.effectiveStatus
    }

    private var statusWash: LinearGradient? {
        if isCompleted {
            return LinearGradient(
                colors: [
                    Color.green.opacity(0.22),
                    Color.green.opacity(0.08),
                    Color.green.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        if isPending {
            return LinearGradient(
                colors: [
                    ordersLogoOrange.opacity(0.28),
                    ordersLogoGold.opacity(0.16),
                    ordersLogoGold.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Obj. \(order.displayOrderNumber)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !badgeStatus.isEmpty {
                        OrderStatusBadge(status: badgeStatus)
                    }

                    Spacer(minLength: 0)

                    if itemsCommission > 0 {
                        Text(OrdersViewFormatting.price(itemsCommission))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ordersLogoOrange)
                            .monospacedDigit()
                    }
                }

                if let name = order.customer_name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(formatOrderDate(order.order_date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                    Text(itemsLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCompleted ? .green : (isPending ? ordersLogoOrange : .secondary))
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    if let statusWash {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(statusWash)
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Detail objednávky

private struct OrderDetailView: View {
    let order: UserOrder
    @Binding var selectedItemContext: OrderItemContext?
    var onOrdersDidUpdate: () -> Void

    @State private var itemForInstallation: OrderItemContext?
    @EnvironmentObject private var authState: AuthState

    /// Provize jen z dokončených položek – nikdy order.amount ani pending.
    private var itemsCommission: Double {
        order.completedCommission
    }

    private var completedItemsCount: Int {
        order.items.filter { $0.statusDisplay.lowercased() == "completed" }.count
    }

    private var isCompleted: Bool {
        order.effectiveStatus == "completed"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroHeader
                if hasCustomerInfo {
                    customerSection
                }
                itemsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Obj. \(order.displayOrderNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $itemForInstallation) { ctx in
            InstallationDateSheet(
                item: ctx.item,
                authToken: authState.authToken,
                onSaved: {
                    itemForInstallation = nil
                    onOrdersDidUpdate()
                },
                onDismiss: { itemForInstallation = nil }
            )
        }
    }

    private var hasCustomerInfo: Bool {
        let name = order.customer_name?.trimmingCharacters(in: .whitespaces) ?? ""
        let phone = order.customer_phone?.trimmingCharacters(in: .whitespaces) ?? ""
        let addr = order.customer_address?.trimmingCharacters(in: .whitespaces) ?? ""
        let notes = order.notes?.trimmingCharacters(in: .whitespaces) ?? ""
        return !name.isEmpty || !phone.isEmpty || !addr.isEmpty || !notes.isEmpty
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(order.displayOrderNumber)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if !order.effectiveStatus.isEmpty {
                            OrderStatusBadge(status: order.effectiveStatus)
                        }
                        Text(formatOrderDate(order.order_date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            HStack(spacing: 0) {
                detailMetric(
                    title: "Provize",
                    value: OrdersViewFormatting.price(itemsCommission),
                    tint: ordersLogoOrange
                )
                Divider().frame(height: 36)
                detailMetric(
                    title: "Položky",
                    value: "\(order.items.count)",
                    tint: .primary
                )
                Divider().frame(height: 36)
                detailMetric(
                    title: "Hotovo",
                    value: order.items.isEmpty ? "—" : "\(completedItemsCount)/\(order.items.count)",
                    tint: isCompleted ? .green : ordersLogoGold
                )
            }
            .padding(.vertical, 4)

            if let url = order.order_url, !url.isEmpty, let link = URL(string: url) {
                Link(destination: link) {
                    Label("Otevřít v prohlížeči", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    if isCompleted {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.20),
                                        Color.green.opacity(0.06),
                                        Color.clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailMetric(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Zákazník")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
                .padding(.horizontal, 4)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                if let name = order.customer_name, !name.isEmpty {
                    customerRow(icon: "person.fill", label: "Jméno", value: name)
                }
                if let phone = order.customer_phone, !phone.isEmpty {
                    customerDivider
                    customerRow(icon: "phone.fill", label: "Telefon", value: phone)
                }
                if let addr = order.customer_address, !addr.isEmpty {
                    customerDivider
                    customerRow(icon: "mappin.and.ellipse", label: "Adresa", value: addr)
                }
                if let notes = order.notes, !notes.isEmpty {
                    customerDivider
                    customerRow(icon: "text.bubble.fill", label: "Poznámky", value: notes)
                }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    private var customerDivider: some View {
        Divider()
            .padding(.leading, 48)
            .opacity(0.5)
    }

    private func customerRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ordersLogoOrange)
                .frame(width: 28, height: 28)
                .background(ordersLogoOrange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Položky")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Spacer()
                Text("\(order.items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if order.items.isEmpty {
                Text("Tato objednávka nemá žádné položky.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(order.items) { item in
                        OrderDetailItemCard(
                            order: order,
                            item: item,
                            onSelect: { selectedItemContext = OrderItemContext(order: order, item: item) },
                            onSetInstallation: { itemForInstallation = OrderItemContext(order: order, item: item) }
                        )
                    }
                }
            }
        }
    }
}

private struct OrderDetailItemCard: View {
    let order: UserOrder
    let item: UserOrderItem
    var onSelect: () -> Void
    var onSetInstallation: () -> Void

    private var installationLine: String {
        let day = item.installation_day?.trimmingCharacters(in: .whitespaces) ?? ""
        let time = item.installation_time?.trimmingCharacters(in: .whitespaces) ?? ""
        if day.isEmpty { return "Termín zatím není" }
        let dateStr: String = {
            if let date = parseInstallationDate(day) {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.locale = Locale(identifier: "cs_CZ")
                return f.string(from: date)
            }
            return day
        }()
        if time.isEmpty { return dateStr }
        return "\(dateStr) · \(time)"
    }

    private var hasInstallation: Bool {
        !(item.installation_day?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
    }

    private var isCompleted: Bool {
        item.statusDisplay.lowercased() == "completed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.item_name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            if let type = item.item_type, !type.isEmpty {
                                Text(type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !item.statusDisplay.isEmpty {
                                OrderStatusBadge(status: item.statusDisplay)
                            }
                        }

                        Label(installationLine, systemImage: hasInstallation ? "calendar.badge.checkmark" : "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(hasInstallation ? .secondary : Color(uiColor: .tertiaryLabel))
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 4) {
                        if item.commission > 0 {
                            Text(OrdersViewFormatting.price(item.commission))
                                .font(.body.weight(.bold))
                                .foregroundStyle(ordersLogoOrange)
                                .monospacedDigit()
                            Text("provize")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onSetInstallation) {
                Label(hasInstallation ? "Změnit termín" : "Vybrat termín", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    if isCompleted {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.18),
                                        Color.green.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Sheet s detailem položky

private struct UserOrderItemDetailSheet: View {
    let orderNumber: String
    let item: UserOrderItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Položka", value: item.item_name)
                    LabeledContent("Objednávka", value: orderNumber)
                    if let type = item.item_type, !type.isEmpty {
                        LabeledContent("Typ", value: type)
                    }
                }
                if !item.installationDateDisplay.isEmpty || (item.installation_time?.isEmpty == false) {
                    Section("Instalace") {
                        if !item.installationDateDisplay.isEmpty {
                            LabeledContent("Datum", value: formatInstallationDate(item.installation_day))
                        }
                        if let time = item.installation_time, !time.isEmpty {
                            LabeledContent("Čas", value: time)
                        }
                    }
                }
                Section("Ceny") {
                    LabeledContent("Základní cena", value: OrdersViewFormatting.price(item.base_price))
                    if item.discount != 0 {
                        LabeledContent("Sleva", value: OrdersViewFormatting.price(item.discount))
                    }
                    LabeledContent("Provize", value: OrdersViewFormatting.price(item.commission))
                }
                if !item.statusDisplay.isEmpty {
                    Section("Stav") {
                        HStack {
                            Spacer()
                            OrderStatusBadge(status: item.statusDisplay)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(item.item_name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatInstallationDate(_ raw: String?) -> String {
        guard let date = parseInstallationDate(raw) else { return raw ?? "—" }
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "cs_CZ")
        return f.string(from: date)
    }
}

// MARK: - Sheet výběru termínu instalace

private struct InstallationDateSheet: View {
    let item: UserOrderItem
    var authToken: String?
    var onSaved: () -> Void
    var onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private static func initialDate(from item: UserOrderItem) -> Date {
        parseInstallationDate(item.installation_day) ?? Date()
    }

    private static func initialTime(from item: UserOrderItem) -> Date {
        guard let timeStr = item.installation_time, !timeStr.isEmpty else {
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        }
        let parts = timeStr.split(separator: ":")
        let h = parts.isEmpty ? 9 : (Int(parts[0]) ?? 9)
        let m = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
        return Calendar.current.date(bySettingHour: min(23, max(0, h)), minute: min(59, max(0, m)), second: 0, of: Date()) ?? Date()
    }

    init(item: UserOrderItem, authToken: String?, onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.item = item
        self.authToken = authToken
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        _selectedDate = State(initialValue: Self.initialDate(from: item))
        _selectedTime = State(initialValue: Self.initialTime(from: item))
    }

    private var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: selectedDate)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: selectedTime)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Položka") {
                    Text(item.item_name)
                        .font(.headline)
                }
                Section("Datum instalace") {
                    DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "cs_CZ"))
                }
                Section("Čas instalace") {
                    DatePicker("Čas", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "cs_CZ"))
                }
                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Termín instalace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") {
                        saveInstallation()
                    }
                    .disabled(isSaving)
                }
            }
            .onDisappear {
                onDismiss()
            }
            .alert("Chyba ukládání", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    showErrorAlert = false
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveInstallation() {
        guard let token = authToken, !token.isEmpty else {
            errorMessage = "Pro uložení se přihlaste."
            showErrorAlert = true
            return
        }
        isSaving = true
        errorMessage = nil
        showErrorAlert = false
        Task {
            do {
                try await UpdateOrderItemInstallationService().updateInstallation(
                    orderItemId: item.id,
                    installationDay: dayString,
                    installationTime: timeString,
                    token: token
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

/// Kontext vybrané položky pro sheet (Identifiable).
struct OrderItemContext: Identifiable {
    let order: UserOrder
    let item: UserOrderItem
    var id: Int { order.id * 100000 + item.id }
}

// MARK: - Shared visuals

private func ordersCardBackground(tint: Color) -> some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.14),
                            tint.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
}

private struct OrdersTopArchGlow: View {
    private let logoOrange = Color(red: 0.97, green: 0.58, blue: 0.12)
    private let logoGold = Color(red: 0.98, green: 0.69, blue: 0.23)
    private let logoPurple = Color(red: 0.30, green: 0.05, blue: 0.22)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 300

            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: logoOrange.opacity(0.22), location: 0),
                        .init(color: logoGold.opacity(0.12), location: 0.4),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [logoPurple.opacity(0.08), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
            .frame(width: width, height: height)
            .mask {
                OrdersTopArchShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.55), location: 0.7),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .frame(height: 300)
    }
}

private struct OrdersTopArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.58))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY * 0.58),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    OrdersView()
        .environmentObject(AuthState())
}
