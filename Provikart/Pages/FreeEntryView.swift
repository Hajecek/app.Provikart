//
//  FreeEntryView.swift
//  Provikart
//
//  Lokální záznamy pro testování (bez API). Data se ukládají do UserDefaults.
//

import SwiftUI

// MARK: - Model

struct FreeEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var note: String
    var commission: Double
    var date: Date

    init(id: UUID = UUID(), name: String, note: String = "", commission: Double = 0, date: Date = Date()) {
        self.id = id
        self.name = name
        self.note = note
        self.commission = commission
        self.date = date
    }
}

// MARK: - Lokální úložiště

final class FreeEntryStore: ObservableObject {
    private static let key = "Provikart.freeEntries"

    @Published var entries: [FreeEntry] = [] {
        didSet { save() }
    }

    var totalCommission: Double {
        entries.reduce(0) { $0 + $1.commission }
    }

    init() { load() }

    func add(_ entry: FreeEntry) {
        entries.insert(entry, at: 0)
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([FreeEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// MARK: - Formátování

private func formatCommission(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

// MARK: - View

struct FreeEntryView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var store = FreeEntryStore()
    @State private var showAddSheet = false
    @State private var showLogoutConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "cs_CZ")
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                commissionSection

                if store.entries.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("Žádné záznamy")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Přidejte svůj první záznam klepnutím na +")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.entries) { entry in
                            entryRow(entry)
                        }
                        .onDelete(perform: store.delete)
                    } header: {
                        Text("Položky")
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Záznamy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        showLogoutConfirm = true
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddFreeEntrySheet(store: store)
            }
            .alert("Odhlásit se?", isPresented: $showLogoutConfirm) {
                Button("Zrušit", role: .cancel) { }
                Button("Odhlásit", role: .destructive) {
                    authState.logOut()
                }
            } message: {
                Text("Vrátíte se na přihlašovací obrazovku.")
            }
        }
    }

    // MARK: - Provize banner

    private var commissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, alignment: .center)
                    Text("Provize")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatCommission(store.totalCommission))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text("Kč")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.caption2)
                    Text("\(store.entries.count) \(entryCountLabel)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Celková provize")
                .textCase(nil)
        }
    }

    private var entryCountLabel: String {
        let count = store.entries.count
        if count == 1 { return "záznam" }
        if count >= 2 && count <= 4 { return "záznamy" }
        return "záznamů"
    }

    // MARK: - Řádek záznamu

    private func entryRow(_ entry: FreeEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(Self.dateFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Text("\(formatCommission(entry.commission)) Kč")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.commission > 0 ? .primary : .tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sheet pro přidání záznamu

private struct AddFreeEntrySheet: View {
    @ObservedObject var store: FreeEntryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var commissionText = ""
    @State private var date = Date()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var parsedCommission: Double {
        let cleaned = commissionText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Základní údaje") {
                    TextField("Název", text: $name)
                    TextField("Poznámka (volitelné)", text: $note)
                }
                Section("Provize") {
                    HStack {
                        TextField("0", text: $commissionText)
                            .keyboardType(.decimalPad)
                        Text("Kč")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Datum") {
                    DatePicker("Datum a čas", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Nový záznam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") {
                        let entry = FreeEntry(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            commission: parsedCommission,
                            date: date
                        )
                        store.add(entry)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    FreeEntryView()
        .environmentObject(AuthState())
}
