//
//  ManagerLocationsSheetView.swift
//  Provikart
//
//  Denní přehled lokalit členů týmu pro manažera.
//

import SwiftUI

@MainActor
final class ManagerLocationsViewModel: ObservableObject {
    @Published var selectedDate: Date = Date()
    @Published var members: [ManagerTeamMember] = []
    @Published var locationsByUser: [Int: [ManagerLocationItem]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let locationsService = ManagerLocationsService()
    private let membersService = ManagerTeamMembersService()

    func load(token: String?) async {
        guard let token, !token.isEmpty else {
            members = []
            locationsByUser = [:]
            errorMessage = "Nejste přihlášeni."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let date = Self.apiDateFormatter.string(from: selectedDate)
            async let fetchedMembers = membersService.fetchMembers(token: token)
            async let fetchedLocations = locationsService.fetchLocations(token: token, workDate: date)
            let (membersPayload, locationsPayload) = try await (fetchedMembers, fetchedLocations)
            members = membersPayload
            locationsByUser = Dictionary(grouping: locationsPayload, by: { $0.userId })
            isLoading = false
        } catch {
            members = []
            locationsByUser = [:]
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func displayName(for member: ManagerTeamMember) -> String {
        if let name = member.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let first = member.firstname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = member.lastname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            return full
        }
        if let username = member.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(member.id)"
    }

    func hasLocation(for member: ManagerTeamMember) -> Bool {
        guard let entries = locationsByUser[member.id], !entries.isEmpty else { return false }
        return entries.contains { !$0.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func userLocations(for member: ManagerTeamMember) -> [ManagerLocationItem] {
        (locationsByUser[member.id] ?? []).sorted {
            ($0.arrivalTime ?? "") < ($1.arrivalTime ?? "")
        }
    }

    private static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

}

struct ManagerLocationsSheetView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManagerLocationsViewModel()

    var body: some View {
        NavigationStack {
            content
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Lokality týmu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                Task {
                    await viewModel.load(token: authState.authToken)
                }
            }
            .refreshable {
                await viewModel.load(token: authState.authToken)
            }
            .task {
                await viewModel.load(token: authState.authToken)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.members.isEmpty {
            ProgressView("Načítám lokality…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage, viewModel.members.isEmpty {
            ContentUnavailableView(
                "Nepodařilo se načíst lokality",
                systemImage: "wifi.exclamationmark",
                description: Text(message)
            )
        } else if viewModel.members.isEmpty {
            ContentUnavailableView(
                "Žádní členové týmu",
                systemImage: "person.3",
                description: Text("Manažer nemá k dispozici žádné členy týmu.")
            )
        } else {
            locationsList
        }
    }

    private var locationsList: some View {
        List {
            Section {
                DatePicker("Den", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Section("Členové týmu (\(viewModel.members.count))") {
                ForEach(viewModel.members) { member in
                    memberRow(member)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func memberRow(_ member: ManagerTeamMember) -> some View {
        let entries = viewModel.userLocations(for: member)
        let hasLocation = viewModel.hasLocation(for: member)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.displayName(for: member))
                    .font(.headline)
                Spacer(minLength: 8)
                statusBadge(hasLocation: hasLocation)
            }

            locationsContent(entries: entries)

            if let note = firstNote(in: entries) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(hasLocation ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(hasLocation ? Color(uiColor: .secondarySystemGroupedBackground) : Color.red.opacity(0.12))
    }

    @ViewBuilder
    private func statusBadge(hasLocation: Bool) -> some View {
        if hasLocation {
            Label("Vyplněno", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("Nezadáno", systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func locationsContent(entries: [ManagerLocationItem]) -> some View {
        if entries.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "mappin.slash")
                    .foregroundStyle(.red)
                Text("Uživatel zatím nezadal lokalitu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
        } else {
            ForEach(entries) { entry in
                locationEntryRow(entry)
            }
        }
    }

    private func locationEntryRow(_ entry: ManagerLocationItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(entry.locationName.isEmpty ? .red : .blue)
            Text(entry.locationName.isEmpty ? "Nezadáno" : entry.locationName)
                .font(.subheadline)
            Spacer(minLength: 8)
            if let arrival = entry.arrivalTime, !arrival.isEmpty {
                Label(arrival, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func firstNote(in entries: [ManagerLocationItem]) -> String? {
        entries.first(where: { !($0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) })?.note
    }
}

#Preview {
    ManagerLocationsSheetView()
        .environmentObject(AuthState())
}
