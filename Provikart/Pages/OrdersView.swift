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

// MARK: - Badge stavu objednávky / položky

private struct OrderStatusBadge: View {
    let status: String

    private var isPending: Bool { status.lowercased() == "pending" }
    private var isCompleted: Bool { status.lowercased() == "completed" }

    var body: some View {
        if isPending {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2.weight(.semibold))
                Text("Čeká")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color(red: 0.95, green: 0.8, blue: 0.25))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(red: 0.22, green: 0.2, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(red: 0.65, green: 0.55, blue: 0.35), lineWidth: 1)
            )
        } else if isCompleted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                Text("Hotovo")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if !status.isEmpty {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Hlavní view

struct OrdersView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet

    @State private var orders: [UserOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedOrder: UserOrder?
    @State private var selectedItemContext: OrderItemContext?
    private let service = UserOrdersService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && orders.isEmpty {
                    ProgressView("Načítám…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let msg = errorMessage {
                    errorView(msg)
                } else if orders.isEmpty {
                    emptyView
                } else {
                    ordersList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Objednávky")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            StatisticsView()
                                .environmentObject(authState)
                                .environment(\.openAddSheet, openAddSheet)
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        NavigationLink {
                            ProblemsView()
                                .environmentObject(authState)
                                .environment(\.openAddSheet, openAddSheet)
                        } label: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if openAddSheet != nil {
                        Button {
                            openAddSheet?()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(item: $selectedOrder) { order in
                OrderDetailView(
                    order: order,
                    selectedItemContext: $selectedItemContext,
                    onOrdersDidUpdate: { Task { await loadOrders() } }
                )
            }
        }
        .sheet(item: $selectedItemContext) { ctx in
            UserOrderItemDetailSheet(orderNumber: ctx.order.displayOrderNumber, item: ctx.item)
        }
        .task { await loadOrders() }
        .refreshable { await loadOrders() }
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Chyba", systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg)
        } actions: {
            Button("Zkusit znovu") { Task { await loadOrders() } }
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

    private var ordersList: some View {
        List {
            ForEach(orders, id: \.id) { order in
                Button {
                    selectedOrder = order
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        OrderListRow(order: order)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
    }

    private func loadOrders() async {
        guard authState.authToken != nil else {
            await MainActor.run { errorMessage = "Pro zobrazení objednávek se přihlaste." }
            return
        }
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let fetched = try await service.fetchOrders(token: authState.authToken)
            await MainActor.run {
                orders = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run {
                orders = []
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Řádek objednávky v seznamu

private struct OrderListRow: View {
    let order: UserOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Obj. \(order.displayOrderNumber)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if !order.statusDisplay.isEmpty {
                    OrderStatusBadge(status: order.statusDisplay)
                }
            }
            if let name = order.customer_name, !name.isEmpty {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(formatOrderDate(order.order_date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let amount = order.amount, amount > 0 {
                    Text(OrdersViewFormatting.price(amount))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if !order.items.isEmpty {
                    Text("\(order.items.count) \(order.items.count == 1 ? "položka" : order.items.count < 5 ? "položky" : "položek")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail objednávky (položky)

private struct OrderDetailView: View {
    let order: UserOrder
    @Binding var selectedItemContext: OrderItemContext?
    var onOrdersDidUpdate: () -> Void

    @State private var itemForInstallation: OrderItemContext?
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        List {
            Section("Objednávka") {
                LabeledContent("Číslo", value: order.displayOrderNumber)
                if let name = order.customer_name, !name.isEmpty {
                    LabeledContent("Zákazník", value: name)
                }
                if let phone = order.customer_phone, !phone.isEmpty {
                    LabeledContent("Telefon", value: phone)
                }
                if let addr = order.customer_address, !addr.isEmpty {
                    LabeledContent("Adresa", value: addr)
                }
                LabeledContent("Datum", value: formatOrderDate(order.order_date))
                if let amount = order.amount {
                    LabeledContent("Částka", value: OrdersViewFormatting.price(amount))
                }
                if !order.statusDisplay.isEmpty {
                    HStack {
                        Text("Stav")
                        Spacer()
                        OrderStatusBadge(status: order.statusDisplay)
                    }
                }
                if let notes = order.notes, !notes.isEmpty {
                    LabeledContent("Poznámky", value: notes)
                }
                if let url = order.order_url, !url.isEmpty, let link = URL(string: url) {
                    Link("Otevřít objednávku", destination: link)
                }
            }
            Section(header: Text("Položky (\(order.items.count))")) {
                ForEach(order.items) { item in
                    OrderDetailItemRow(
                        order: order,
                        item: item,
                        onSelect: { selectedItemContext = OrderItemContext(order: order, item: item) },
                        onSetInstallation: { itemForInstallation = OrderItemContext(order: order, item: item) }
                    )
                }
            }
        }
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
}

// MARK: - Řádek položky v detailu objednávky (tap = detail, ikona = datum instalace)

private struct OrderDetailItemRow: View {
    let order: UserOrder
    let item: UserOrderItem
    var onSelect: () -> Void
    var onSetInstallation: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    UserOrderItemRow(item: item)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onSetInstallation) {
                Image(systemName: "calendar.badge.clock")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Řádek položky (jen obsah)

private struct UserOrderItemRow: View {
    let item: UserOrderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.item_name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                if let type = item.item_type, !type.isEmpty {
                    Text(type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.base_price > 0 {
                    Text(OrdersViewFormatting.price(item.base_price))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if !item.statusDisplay.isEmpty {
                    OrderStatusBadge(status: item.statusDisplay)
                }
            }
        }
        .padding(.vertical, 4)
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
    /// Token předaný z rodiče (OrderDetailView), aby sheet měl jistotu přístupu k přihlášení.
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
