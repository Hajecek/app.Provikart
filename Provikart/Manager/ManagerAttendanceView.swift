//
//  ManagerAttendanceView.swift
//  Provikart
//
//  Manažerský přehled docházky týmu.
//

import SwiftUI

@MainActor
final class ManagerAttendanceViewModel: ObservableObject {
    @Published var users: [ManagerAttendanceUser] = []
    @Published var days: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedMonthDate: Date = Date()
    @Published var savingKey: String?

    private let service = ManagerAttendanceService()

    func loadAttendance(token: String?) async {
        guard let token, !token.isEmpty else {
            users = []
            days = []
            errorMessage = "Nejste přihlášeni."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let month = Self.monthAPIFormatter.string(from: selectedMonthDate)
            let payload = try await service.fetchAttendance(token: token, month: month, includeSelf: true)
            users = payload.users
            days = payload.days
            isLoading = false
        } catch {
            users = []
            days = []
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func moveMonth(by offset: Int) {
        guard let updated = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) else { return }
        selectedMonthDate = updated
    }

    func updateAttendance(token: String?, userId: Int, day: String, status: String) async {
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return
        }

        guard let userIndex = users.firstIndex(where: { $0.userId == userId }) else { return }
        let key = "\(userId)_\(day)"
        savingKey = key
        let previousEntry = users[userIndex].attendance[day]

        var updatedAttendance = users[userIndex].attendance
        updatedAttendance[day] = ManagerAttendanceEntry(
            status: status,
            note: previousEntry?.note,
            updatedAt: previousEntry?.updatedAt,
            updatedBy: previousEntry?.updatedBy,
            isDefault: false
        )
        users[userIndex] = ManagerAttendanceUser(
            userId: users[userIndex].userId,
            name: users[userIndex].name,
            firstname: users[userIndex].firstname,
            lastname: users[userIndex].lastname,
            username: users[userIndex].username,
            profileImage: users[userIndex].profileImage,
            attendance: updatedAttendance
        )

        do {
            try await service.updateAttendance(token: token, userId: userId, day: day, status: status)
            savingKey = nil
        } catch {
            if let rollback = previousEntry {
                updatedAttendance[day] = rollback
            }
            users[userIndex] = ManagerAttendanceUser(
                userId: users[userIndex].userId,
                name: users[userIndex].name,
                firstname: users[userIndex].firstname,
                lastname: users[userIndex].lastname,
                username: users[userIndex].username,
                profileImage: users[userIndex].profileImage,
                attendance: updatedAttendance
            )
            savingKey = nil
            errorMessage = error.localizedDescription
        }
    }

    var monthTitle: String {
        Self.monthTitleFormatter.string(from: selectedMonthDate).capitalized
    }

    private static let monthAPIFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "LLLL yyyy"
        return f
    }()
}

struct ManagerAttendanceView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerAttendanceViewModel()
    @State private var selectedCell: AttendanceCellSelection?
    @State private var searchText = ""
    @State private var isLocationsSheetPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.users.isEmpty {
                    ProgressView("Načítám docházku…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.users.isEmpty {
                    ContentUnavailableView(
                        "Nepodařilo se načíst docházku",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                } else if viewModel.users.isEmpty {
                    ContentUnavailableView(
                        "Žádní členové týmu",
                        systemImage: "person.3",
                        description: Text("Pro vybraný měsíc nejsou dostupná data.")
                    )
                } else {
                    List {
                        Section {
                            monthSwitchRow
                        }

                        ForEach(filteredUsers) { user in
                            Section {
                                userHeaderRow(user)
                                userDaysRow(user)
                            } header: {
                                Text(displayName(for: user))
                            } footer: {
                                userFooter(user)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(viewModel.monthTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isLocationsSheetPresented = true
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .accessibilityLabel("Lokality týmu")
                    ProfileBarButton()
                }
            }
            .refreshable {
                await viewModel.loadAttendance(token: authState.authToken)
            }
            .task {
                await viewModel.loadAttendance(token: authState.authToken)
            }
            .onChange(of: viewModel.selectedMonthDate) { _, _ in
                Task {
                    await viewModel.loadAttendance(token: authState.authToken)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Hledat člena týmu")
            .confirmationDialog(
                "Změnit docházku",
                isPresented: Binding(
                    get: { selectedCell != nil },
                    set: { if !$0 { selectedCell = nil } }
                ),
                titleVisibility: .visible,
                presenting: selectedCell
            ) { selection in
                Button("Práce (P)") {
                    Task {
                        await viewModel.updateAttendance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            status: "P"
                        )
                    }
                }
                Button("Volno (V)") {
                    Task {
                        await viewModel.updateAttendance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            status: "V"
                        )
                    }
                }
                Button("Nemoc (N)") {
                    Task {
                        await viewModel.updateAttendance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            status: "N"
                        )
                    }
                }
                Button("Zrušit", role: .cancel) {}
            } message: { selection in
                Text("\(displayName(for: selection.user)) - \(dialogDate(selection.day))")
            }
            .sheet(isPresented: $isLocationsSheetPresented) {
                ManagerLocationsSheetView()
                    .environmentObject(authState)
            }
        }
    }

    private var monthSwitchRow: some View {
        HStack {
            Button {
                viewModel.moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(viewModel.monthTitle)
                .font(.headline.weight(.semibold))
            Spacer()
            Button {
                viewModel.moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }


    private func userHeaderRow(_ user: ManagerAttendanceUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(initials(for: user))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                )
            Text("Docházka za měsíc")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            statusBadge("P", count: statusCount("P", user: user))
            statusBadge("V", count: statusCount("V", user: user))
            statusBadge("N", count: statusCount("N", user: user))
        }
    }

    private func userDaysRow(_ user: ManagerAttendanceUser) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.days, id: \.self) { day in
                    let entry = user.attendance[day]
                    let status = normalizedStatus(entry?.status ?? "?")
                    let key = "\(user.userId)_\(day)"
                    VStack(spacing: 4) {
                        Text(dayNumber(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            selectedCell = AttendanceCellSelection(user: user, day: day, currentStatus: status)
                        } label: {
                            ZStack {
                                Text(status)
                                    .font(.caption.bold())
                                    .foregroundStyle(statusColor(status))
                                    .frame(width: 28, height: 28)
                                    .background(statusColor(status).opacity(0.16))
                                    .clipShape(Circle())
                                if viewModel.savingKey == key {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        if !(entry?.note?.isEmpty ?? true) {
                            Image(systemName: "text.bubble")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Color.clear.frame(width: 10, height: 10)
                        }
                    }
                    .frame(width: 34)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func statusBadge(_ status: String, count: Int) -> some View {
        let color = statusColor(status)
        return HStack(spacing: 4) {
            Text(status)
                .font(.caption2.bold())
            Text("\(count)")
                .font(.caption.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func userFooter(_ user: ManagerAttendanceUser) -> some View {
        let withNote = viewModel.days.filter { day in
            !(user.attendance[day]?.note?.isEmpty ?? true)
        }.count
        return HStack(spacing: 8) {
            Text("Pracovní dny: \(statusCount("P", user: user))")
            if withNote > 0 {
                Text("Poznámky: \(withNote)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func displayName(for user: ManagerAttendanceUser) -> String {
        if !user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return user.name
        }
        if let username = user.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(user.userId)"
    }

    private func normalizedStatus(_ raw: String) -> String {
        let status = raw.uppercased()
        if status == "D" {
            return "V"
        }
        return status
    }

    private func statusCount(_ status: String, user: ManagerAttendanceUser) -> Int {
        viewModel.days.reduce(into: 0) { partial, day in
            let value = normalizedStatus(user.attendance[day]?.status ?? "")
            if value == status {
                partial += 1
            }
        }
    }

    private var filteredUsers: [ManagerAttendanceUser] {
        let query = normalizedSearchText(searchText)
        return viewModel.users.filter { user in
            guard !query.isEmpty else { return true }
            let haystack = searchableText(for: user)
            return query.allSatisfy { haystack.contains($0) }
        }
    }

    private func searchableText(for user: ManagerAttendanceUser) -> String {
        let fullName = "\(user.firstname ?? "") \(user.lastname ?? "")"
        let pieces = [
            displayName(for: user),
            fullName,
            user.firstname ?? "",
            user.lastname ?? "",
            user.username ?? ""
        ]
        return normalizedSearchString(pieces.joined(separator: " "))
    }

    private func normalizedSearchText(_ text: String) -> [String] {
        normalizedSearchString(text)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalizedSearchString(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }


    private func statusColor(_ status: String) -> Color {
        switch status {
        case "P": return .green
        case "V": return .blue
        case "N": return .red
        default: return .secondary
        }
    }

    private func initials(for user: ManagerAttendanceUser) -> String {
        let first = (user.firstname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (user.lastname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = first.first, let l = last.first {
            return "\(String(f).uppercased())\(String(l).uppercased())"
        }
        if let f = first.first {
            return String(f).uppercased()
        }
        if let u = user.username?.first {
            return String(u).uppercased()
        }
        return "?"
    }

    private func dayNumber(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayNumberFormatter.string(from: date)
    }

    private func dialogDate(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayDialogFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "d"
        return f
    }()

    private static let dayDialogFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()
}

private struct AttendanceCellSelection: Identifiable {
    let user: ManagerAttendanceUser
    let day: String
    let currentStatus: String
    var id: String { "\(user.userId)-\(day)" }
}

#Preview {
    ManagerAttendanceView()
        .environmentObject(AuthState())
}
