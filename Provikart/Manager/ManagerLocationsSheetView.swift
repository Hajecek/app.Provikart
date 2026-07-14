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
            return "checkmark"
        case .absent(let status):
            return status == "N" ? "cross.case.fill" : "sun.max.fill"
        case .missing:
            return "exclamationmark"
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

    var sortPriority: Int {
        switch self {
        case .missing: return 0
        case .reported: return 1
        case .absent: return 2
        }
    }
}

private enum ManagerLocationFilter: String, CaseIterable, Identifiable {
    case all = "Všichni"
    case reported = "Vyplněno"
    case missing = "Nezadáno"
    case absent = "Nepřítomni"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "person.3.fill"
        case .reported: return "checkmark.circle.fill"
        case .missing: return "exclamationmark.circle.fill"
        case .absent: return "calendar.circle.fill"
        }
    }
}

private extension ManagerTeamMember {
    var profileImageURL: URL? {
        guard let name = profile_image?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
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

    var filledCount: Int {
        members.filter { isReported(for: $0) }.count
    }

    var absentCount: Int {
        members.filter { isAbsent(for: $0) }.count
    }

    var missingCount: Int {
        members.filter { isMissingLocation(for: $0) }.count
    }

    var completionRate: Double {
        guard !members.isEmpty else { return 0 }
        return Double(filledCount) / Double(members.count)
    }

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

    fileprivate func filteredMembers(search: String, filter: ManagerLocationFilter) -> [ManagerTeamMember] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return members
            .filter { member in
                switch filter {
                case .all:
                    return true
                case .reported:
                    return isReported(for: member)
                case .missing:
                    return isMissingLocation(for: member)
                case .absent:
                    return isAbsent(for: member)
                }
            }
            .filter { member in
                guard !query.isEmpty else { return true }
                return displayName(for: member).lowercased().contains(query)
                    || (member.username?.lowercased().contains(query) ?? false)
            }
            .sorted { lhs, rhs in
                let leftStatus = locationStatus(for: lhs)
                let rightStatus = locationStatus(for: rhs)
                if leftStatus.sortPriority != rightStatus.sortPriority {
                    return leftStatus.sortPriority < rightStatus.sortPriority
                }
                return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
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

    func initials(for member: ManagerTeamMember) -> String {
        let name = displayName(for: member)
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        if !letters.isEmpty {
            return letters.uppercased()
        }
        return String(name.prefix(1)).uppercased()
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

    func shiftDate(by days: Int) {
        guard let updated = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = updated
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

    static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "EEEE"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "d. MMMM yyyy"
        return f
    }()
}

struct ManagerLocationsSheetView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManagerLocationsViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: ManagerLocationFilter = .all

    private var filteredMembers: [ManagerTeamMember] {
        viewModel.filteredMembers(search: searchText, filter: selectedFilter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.members.isEmpty {
                    loadingView
                } else if let message = viewModel.errorMessage, viewModel.members.isEmpty {
                    errorView(message)
                } else if viewModel.members.isEmpty {
                    emptyTeamView
                } else {
                    mainContent
                }
            }
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Hledat člena týmu")
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

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                dateNavigationCard
                summaryHeroCard
                filterChips
                membersSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Načítám lokality…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst lokality", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Zkusit znovu") {
                Task {
                    await viewModel.load(token: authState.authToken)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyTeamView: some View {
        ContentUnavailableView(
            "Žádní členové týmu",
            systemImage: "person.3",
            description: Text("Manažer nemá k dispozici žádné členy týmu.")
        )
    }

    private var dateNavigationCard: some View {
        HStack(spacing: 12) {
            dateStepButton(systemName: "chevron.left") {
                viewModel.shiftDate(by: -1)
            }

            VStack(spacing: 2) {
                Text(ManagerLocationsViewModel.weekdayFormatter.string(from: viewModel.selectedDate).capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(ManagerLocationsViewModel.dayFormatter.string(from: viewModel.selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            dateStepButton(systemName: "chevron.right") {
                viewModel.shiftDate(by: 1)
            }

            if !Calendar.current.isDateInToday(viewModel.selectedDate) {
                Button("Dnes") {
                    viewModel.selectedDate = Date()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground(tint: .blue))
    }

    private var summaryHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                completionRing

                VStack(alignment: .leading, spacing: 10) {
                    Text("Přehled hlášení")
                        .font(.headline)
                    Text("\(viewModel.members.count) členů týmu")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        summaryStatRow(
                            title: "Vyplněno",
                            value: viewModel.filledCount,
                            tint: .green,
                            icon: "checkmark.circle.fill"
                        )
                        summaryStatRow(
                            title: "Nezadáno",
                            value: viewModel.missingCount,
                            tint: .orange,
                            icon: "exclamationmark.circle.fill"
                        )
                        summaryStatRow(
                            title: "Nepřítomni",
                            value: viewModel.absentCount,
                            tint: .blue,
                            icon: "calendar.circle.fill"
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground(tint: .green))
    }

    private var completionRing: some View {
        let rate = viewModel.completionRate
        let percentage = Int((rate * 100).rounded())

        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: rate)
                .stroke(
                    AngularGradient(
                        colors: [.green.opacity(0.7), .green],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(percentage)%")
                    .font(.title3.weight(.bold))
                Text("hotovo")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vyplněno \(percentage) procent")
    }

    private func summaryStatRow(title: String, value: Int, tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ManagerLocationFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(_ filter: ManagerLocationFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = count(for: filter)

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.iconName)
                    .font(.caption.weight(.semibold))
                Text(filter.rawValue)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08), in: Capsule())
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                } else {
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            Capsule()
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func count(for filter: ManagerLocationFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.members.count
        case .reported:
            return viewModel.filledCount
        case .missing:
            return viewModel.missingCount
        case .absent:
            return viewModel.absentCount
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Členové týmu")
                    .font(.headline)
                Spacer()
                Text("\(filteredMembers.count) z \(viewModel.members.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if filteredMembers.isEmpty {
                ContentUnavailableView {
                    Label("Žádné výsledky", systemImage: "magnifyingglass")
                } description: {
                    Text("Zkuste upravit filtr nebo hledaný výraz.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredMembers) { member in
                        memberCard(member)
                    }
                }
            }
        }
    }

    private func memberCard(_ member: ManagerTeamMember) -> some View {
        let entries = viewModel.userLocations(for: member)
        let status = viewModel.locationStatus(for: member)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                memberAvatar(member, status: status)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayName(for: member))
                        .font(.headline)
                        .lineLimit(1)
                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                statusBadge(status)
            }

            locationsContent(entries: entries, status: status)

            if status.showsLocationDetails, let note = firstNote(in: entries) {
                noteCallout(note)
            }
        }
        .padding(16)
        .background(cardBackground(tint: status.tint))
    }

    private func memberAvatar(_ member: ManagerTeamMember, status: ManagerLocationReportStatus) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = member.profileImageURL {
                    AuthenticatedProfileImageView(
                        url: url,
                        token: authState.authToken,
                        size: 46
                    )
                } else {
                    Circle()
                        .fill(status.tint.opacity(0.14))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Text(viewModel.initials(for: member))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(status.tint)
                        }
                }
            }
            .overlay {
                Circle()
                    .stroke(status.tint.opacity(0.35), lineWidth: 2)
            }

            Circle()
                .fill(status.tint)
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: status.iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 2, y: 2)
        }
    }

    private func statusBadge(_ status: ManagerLocationReportStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.badgeIconName)
            Text(status.badgeText)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.tint.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func locationsContent(entries: [ManagerLocationItem], status: ManagerLocationReportStatus) -> some View {
        if case .absent = status {
            emptyStateRow(status: status)
        } else if entries.isEmpty {
            emptyStateRow(status: status)
        } else {
            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    locationEntryCard(entry)
                }
            }
        }
    }

    private func emptyStateRow(status: ManagerLocationReportStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.emptyContentIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.tint)
                .frame(width: 28, height: 28)
                .background(status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(status.emptyContentText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func locationEntryCard(_ entry: ManagerLocationItem) -> some View {
        let hasLocation = !entry.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(hasLocation ? .blue : .red)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasLocation ? entry.locationName : "Nezadáno")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hasLocation ? Color.primary : Color.red)
                    .lineLimit(2)

                if let arrival = entry.arrivalTime, !arrival.isEmpty {
                    Label("Příjezd \(arrival)", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let arrival = entry.arrivalTime, !arrival.isEmpty {
                Text(arrival)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func noteCallout(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func firstNote(in entries: [ManagerLocationItem]) -> String? {
        entries.first(where: { !($0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) })?.note
    }

    private func dateStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(tint: Color) -> some View {
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
}

#Preview {
    ManagerLocationsSheetView()
        .environmentObject(AuthState())
}
