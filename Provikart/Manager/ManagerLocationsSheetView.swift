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

            Section {
                summaryStrip
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section("Členové týmu (\(viewModel.members.count))") {
                ForEach(viewModel.members) { member in
                    memberRow(member)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var summaryStrip: some View {
        let filledCount = viewModel.members.filter { viewModel.hasLocation(for: $0) }.count
        let missingCount = max(0, viewModel.members.count - filledCount)

        return HStack(spacing: 10) {
            summaryCard(
                title: "Vyplněno",
                value: "\(filledCount)",
                icon: "checkmark.circle.fill",
                tint: .green
            )
            summaryCard(
                title: "Nezadáno",
                value: "\(missingCount)",
                icon: "exclamationmark.circle.fill",
                tint: .orange
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func memberRow(_ member: ManagerTeamMember) -> some View {
        let entries = viewModel.userLocations(for: member)
        let hasLocation = viewModel.hasLocation(for: member)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Circle()
                    .fill((hasLocation ? Color.green : Color.orange).opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: hasLocation ? "person.fill.checkmark" : "person.fill.xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(hasLocation ? .green : .orange)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.displayName(for: member))
                        .font(.headline)
                        .lineLimit(1)
                    Text(hasLocation ? "Lokalita nahlášena" : "Čeká na nahlášení lokality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                statusBadge(hasLocation: hasLocation)
            }

            locationsContent(entries: entries)

            if let note = firstNote(in: entries) {
                Label(note, systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(rowBackground(hasLocation: hasLocation))
    }

    @ViewBuilder
    private func statusBadge(hasLocation: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: hasLocation ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(hasLocation ? "Vyplněno" : "Nezadáno")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(hasLocation ? Color.green : Color.red)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((hasLocation ? Color.green : Color.red).opacity(0.14))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func locationsContent(entries: [ManagerLocationItem]) -> some View {
        if entries.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "mappin.slash")
                    .foregroundStyle(.orange)
                Text("Uživatel zatím nezadal lokalitu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                locationEntryRow(entry, showDivider: index < entries.count - 1)
            }
        }
    }

    private func locationEntryRow(_ entry: ManagerLocationItem, showDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(entry.locationName.isEmpty ? .red : .blue)
                Text(entry.locationName.isEmpty ? "Nezadáno" : entry.locationName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(entry.locationName.isEmpty ? .red : .primary)
                Spacer(minLength: 8)
                if let arrival = entry.arrivalTime, !arrival.isEmpty {
                    Label(arrival, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if showDivider {
                Divider()
                    .opacity(0.25)
            }
        }
    }

    private func firstNote(in entries: [ManagerLocationItem]) -> String? {
        entries.first(where: { !($0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) })?.note
    }

    @ViewBuilder
    private func rowBackground(hasLocation: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            shape
                .fill(
                    hasLocation
                        ? Color(uiColor: .secondarySystemGroupedBackground)
                        : Color.orange.opacity(0.09)
                )
            shape
                .stroke(
                    hasLocation
                        ? Color.primary.opacity(0.05)
                        : Color.orange.opacity(0.25),
                    lineWidth: 1
                )
        }
    }
}

#Preview {
    ManagerLocationsSheetView()
        .environmentObject(AuthState())
}
