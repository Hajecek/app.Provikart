//
//  ManagerLocationsSheetView.swift
//  Provikart
//
//  Denní přehled lokalit členů týmu pro manažera.
//

import SwiftUI

enum ManagerLocationReportStatus: Equatable {
    case reported
    case absent(String)
    case missing

    var subtitle: String {
        switch self {
        case .reported:
            return "Lokalita nahlášena"
        case .absent(let status):
            return status == "N" ? "Nemoc" : "Volno / dovolená"
        case .missing:
            return "Čeká na nahlášení lokality"
        }
    }

    var badgeText: String {
        switch self {
        case .reported:
            return "Vyplněno"
        case .absent:
            return "Nepřítomen"
        case .missing:
            return "Nezadáno"
        }
    }

    var iconName: String {
        switch self {
        case .reported:
            return "person.fill.checkmark"
        case .absent:
            return "calendar"
        case .missing:
            return "person.fill.xmark"
        }
    }

    var badgeIconName: String {
        switch self {
        case .reported:
            return "checkmark.circle.fill"
        case .absent:
            return "calendar.circle.fill"
        case .missing:
            return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .reported:
            return .green
        case .absent(let status):
            return status == "N" ? .red : .blue
        case .missing:
            return .orange
        }
    }

    var rowFill: Color {
        switch self {
        case .reported:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .absent:
            return tint.opacity(0.08)
        case .missing:
            return Color.orange.opacity(0.09)
        }
    }

    var rowStroke: Color {
        switch self {
        case .reported:
            return Color.primary.opacity(0.05)
        case .absent:
            return tint.opacity(0.22)
        case .missing:
            return Color.orange.opacity(0.25)
        }
    }

    var emptyContentText: String {
        switch self {
        case .reported:
            return "Uživatel zatím nezadal lokalitu"
        case .absent(let status):
            return status == "N" ? "Uživatel je nemocný" : "Uživatel má volno / dovolenou"
        case .missing:
            return "Uživatel zatím nezadal lokalitu"
        }
    }

    var emptyContentIcon: String {
        switch self {
        case .reported, .missing:
            return "mappin.slash"
        case .absent:
            return "calendar"
        }
    }

    var isAbsent: Bool {
        if case .absent = self {
            return true
        }
        return false
    }

    var showsLocationDetails: Bool {
        !isAbsent
    }
}

@MainActor
final class ManagerLocationsViewModel: ObservableObject {
    @Published var selectedDate: Date = Date()
    @Published var members: [ManagerTeamMember] = []
    @Published var locationsByUser: [Int: [ManagerLocationItem]] = [:]
    @Published var attendanceByUser: [Int: ManagerAttendanceUser] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let locationsService = ManagerLocationsService()
    private let membersService = ManagerTeamMembersService()
    private let attendanceService = ManagerAttendanceService()

    func load(token: String?) async {
        guard let token, !token.isEmpty else {
            members = []
            locationsByUser = [:]
            attendanceByUser = [:]
            errorMessage = "Nejste přihlášeni."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let date = Self.apiDateFormatter.string(from: selectedDate)
            let month = Self.monthAPIFormatter.string(from: selectedDate)
            async let fetchedMembers = membersService.fetchMembers(token: token)
            async let fetchedLocations = locationsService.fetchLocations(token: token, workDate: date)
            async let fetchedAttendance = attendanceService.fetchAttendance(token: token, month: month, includeSelf: true)
            let (membersPayload, locationsPayload, attendancePayload) = try await (fetchedMembers, fetchedLocations, fetchedAttendance)
            members = membersPayload
            locationsByUser = Dictionary(grouping: locationsPayload, by: { $0.userId })
            attendanceByUser = attendancePayload.users.reduce(into: [:]) { result, user in
                result[user.userId] = user
            }
            isLoading = false
        } catch {
            members = []
            locationsByUser = [:]
            attendanceByUser = [:]
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

    func locationStatus(for member: ManagerTeamMember) -> ManagerLocationReportStatus {
        if let absence = absenceStatus(for: member) {
            return .absent(absence)
        }
        if hasLocation(for: member) {
            return .reported
        }
        return .missing
    }

    func isReported(for member: ManagerTeamMember) -> Bool {
        locationStatus(for: member) == .reported
    }

    func isMissingLocation(for member: ManagerTeamMember) -> Bool {
        locationStatus(for: member) == .missing
    }

    func isAbsent(for member: ManagerTeamMember) -> Bool {
        locationStatus(for: member).isAbsent
    }

    private func absenceStatus(for member: ManagerTeamMember) -> String? {
        let day = Self.apiDateFormatter.string(from: selectedDate)
        guard let entry = attendanceByUser[member.id]?.attendance[day] else {
            return nil
        }
        let status = Self.normalizedAttendanceStatus(entry.status)
        return ["V", "N"].contains(status) ? status : nil
    }

    private static func normalizedAttendanceStatus(_ raw: String) -> String {
        let status = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return status == "D" ? "V" : status
    }

    private static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthAPIFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
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
        let filledCount = viewModel.members.filter { viewModel.isReported(for: $0) }.count
        let absentCount = viewModel.members.filter { viewModel.isAbsent(for: $0) }.count
        let missingCount = viewModel.members.filter { viewModel.isMissingLocation(for: $0) }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Přehled hlášení", systemImage: "list.bullet.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(viewModel.members.count) členů")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                summaryMetric(
                    title: "Vyplněno",
                    value: "\(filledCount)",
                    icon: "checkmark.circle.fill",
                    tint: .green
                )
                summaryMetric(
                    title: "Nepřítomni",
                    value: "\(absentCount)",
                    icon: "calendar.circle.fill",
                    tint: .blue
                )
                summaryMetric(
                    title: "Nezadáno",
                    value: "\(missingCount)",
                    icon: "exclamationmark.circle.fill",
                    tint: .orange
                )
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func memberRow(_ member: ManagerTeamMember) -> some View {
        let entries = viewModel.userLocations(for: member)
        let status = viewModel.locationStatus(for: member)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Circle()
                    .fill(status.tint.opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: status.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.tint)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.displayName(for: member))
                        .font(.headline)
                        .lineLimit(1)
                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                statusBadge(status)
            }

            locationsContent(entries: entries, status: status)

            if status.showsLocationDetails, let note = firstNote(in: entries) {
                Label(note, systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(rowBackground(status: status))
    }

    @ViewBuilder
    private func statusBadge(_ status: ManagerLocationReportStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.badgeIconName)
            Text(status.badgeText)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(status.tint.opacity(0.14))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func locationsContent(entries: [ManagerLocationItem], status: ManagerLocationReportStatus) -> some View {
        if case .absent = status {
            HStack(spacing: 6) {
                Image(systemName: status.emptyContentIcon)
                    .foregroundStyle(status.tint)
                Text(status.emptyContentText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else if entries.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: status.emptyContentIcon)
                    .foregroundStyle(status.tint)
                Text(status.emptyContentText)
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
    private func rowBackground(status: ManagerLocationReportStatus) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            shape
                .fill(status.rowFill)
            shape
                .stroke(status.rowStroke, lineWidth: 1)
        }
    }
}

#Preview {
    ManagerLocationsSheetView()
        .environmentObject(AuthState())
}
