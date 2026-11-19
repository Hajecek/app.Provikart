//
//  NationalIncompleteOrdersView.swift
//  Provikart
//
//  Kontrola objednávek národního manažera (web /admin/incomplete-orders):
//  nedokončené objednávky založené manažery, filtr stavu a detail s vývojem.
//

import SwiftUI

@MainActor
final class NationalIncompleteOrdersViewModel: ObservableObject {
    @Published private(set) var items: [NationalIncompleteOrder] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var statusFilter: NationalIncompleteOrder.Status?
    @Published var searchText = ""

    private let service = NationalManagerService()
    private var didLoad = false

    var filtered: [NationalIncompleteOrder] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { order in
            if let statusFilter, order.status != statusFilter { return false }
            guard !q.isEmpty else { return true }
            return order.orderNumber.lowercased().contains(q)
                || order.sales.lowercased().contains(q)
                || order.manager.lowercased().contains(q)
                || order.team.lowercased().contains(q)
        }
    }

    func count(_ status: NationalIncompleteOrder.Status?) -> Int {
        guard let status else { return items.count }
        return items.filter { $0.status == status }.count
    }

    func loadIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await load(token: token)
    }

    func load(token: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.fetchIncompleteOrders(token: token)
            errorMessage = nil
            didLoad = true
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }
}

extension NationalIncompleteOrder.Status {
    var tint: Color {
        switch self {
        case .created: return SV.sky
        case .open: return SV.accent
        case .completed: return SV.good
        }
    }

    var icon: String {
        switch self {
        case .created: return "doc.badge.plus"
        case .open: return "clock"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

enum NationalDateLabel {
    private static let input: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let output: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "d. M. yyyy HH:mm"
        return f
    }()

    static func format(_ raw: String) -> String {
        guard let date = input.date(from: raw) else { return raw }
        return output.string(from: date)
    }
}

struct NationalIncompleteOrdersView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = NationalIncompleteOrdersViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kontrola objednávek")
                            .font(.largeTitle.weight(.bold))
                        Text("Nedokončené objednávky založené manažery")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Picker("Stav", selection: $viewModel.statusFilter) {
                        Text("Vše \(viewModel.count(nil))").tag(NationalIncompleteOrder.Status?.none)
                        Text("Vytvořeno \(viewModel.count(.created))").tag(NationalIncompleteOrder.Status?.some(.created))
                        Text("Otevřeno \(viewModel.count(.open))").tag(NationalIncompleteOrder.Status?.some(.open))
                        Text("Hotovo \(viewModel.count(.completed))").tag(NationalIncompleteOrder.Status?.some(.completed))
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Načítám objednávky…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nepodařilo se načíst", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Zkusit znovu") { Task { await viewModel.load(token: authState.authToken) } }
                            .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.filtered.isEmpty {
                    ContentUnavailableView(
                        "Žádné objednávky",
                        systemImage: "checkmark.circle",
                        description: Text("V tomto filtru nejsou žádné objednávky ke kontrole.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.filtered) { order in
                        NavigationLink {
                            NationalIncompleteOrderDetailView(order: order)
                        } label: {
                            row(order)
                        }
                        .padding(14)
                        .background(SVCardBackground(radius: 20, tint: order.status.tint))
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { ManagerScreenBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ManagerToolbarLogo() }
                ToolbarItem(placement: .topBarTrailing) { ProfileBarButton() }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $viewModel.searchText, prompt: "Číslo objednávky, obchodník…")
            .task { await viewModel.loadIfNeeded(token: authState.authToken) }
            .refreshable { await viewModel.load(token: authState.authToken) }
        }
    }

    private func row(_ order: NationalIncompleteOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.orderNumber.isEmpty ? "Bez čísla" : order.orderNumber)
                    .font(.headline.monospacedDigit())
                Spacer(minLength: 8)
                SVChip(text: order.status.label, icon: order.status.icon, tint: order.status.tint)
            }
            Label(order.sales, systemImage: "person")
                .font(.subheadline)
            HStack(spacing: 6) {
                Text("Manažer: \(order.manager)")
                if !order.team.isEmpty { Text("· \(order.team)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(NationalDateLabel.format(order.createdAt))
                if !order.statements.isEmpty {
                    Text("· \(order.statements.count)× vývoj")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NationalIncompleteOrderDetailView: View {
    let order: NationalIncompleteOrder

    var body: some View {
        Form {
            Section {
                LabeledContent("Číslo objednávky", value: order.orderNumber.isEmpty ? "—" : order.orderNumber)
                LabeledContent("Stav") {
                    SVChip(text: order.status.label, icon: order.status.icon, tint: order.status.tint)
                }
                LabeledContent("Obchodník", value: order.sales)
                LabeledContent("Manažer", value: order.manager)
                if !order.team.isEmpty {
                    LabeledContent("Tým", value: order.team)
                }
                LabeledContent("Založeno", value: NationalDateLabel.format(order.createdAt))
            }

            if !order.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Údaje objednávky") {
                    Text(order.note)
                        .textSelection(.enabled)
                }
            }

            Section("Vývoj") {
                if order.statements.isEmpty {
                    Text("Zatím bez vývoje.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(order.statements.enumerated()), id: \.offset) { _, statement in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(statement.authorName)
                                    .font(.subheadline.weight(.semibold))
                                Text(statement.kind)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(NationalDateLabel.format(statement.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(statement.text)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(order.orderNumber.isEmpty ? "Objednávka" : order.orderNumber)
        .navigationBarTitleDisplayMode(.inline)
    }
}
