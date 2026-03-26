//
//  UserAttendanceView.swift
//  Provikart
//
//  Vlastní docházka uživatele (náhled + editace statusu a poznámky).
//

import SwiftUI

@MainActor
final class UserAttendanceViewModel: ObservableObject {
    @Published var user: UserAttendanceUser?
    @Published var days: [String] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var selectedMonthDate: Date = Date()

    private let service = UserAttendanceService()

    func loadAttendance(token: String?) async {
        guard let token, !token.isEmpty else {
            user = nil
            days = []
            errorMessage = "Nejste přihlášeni."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let month = Self.monthAPIFormatter.string(from: selectedMonthDate)
            let payload = try await service.fetchAttendance(token: token, month: month)
            user = payload.user
            days = payload.days
            isLoading = false
        } catch {
            user = nil
            days = []
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func moveMonth(by offset: Int) {
        guard let updated = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) else { return }
        selectedMonthDate = updated
    }

    func updateAttendance(token: String?, day: String, status: String, note: String?) async {
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return
        }
        guard var currentUser = user else { return }
        let previous = currentUser.attendance[day]
        var updated = currentUser.attendance
        updated[day] = UserAttendanceEntry(
            status: status,
            note: note,
            updatedAt: previous?.updatedAt,
            updatedBy: previous?.updatedBy,
            isDefault: false
        )
        currentUser = UserAttendanceUser(
            userId: currentUser.userId,
            name: currentUser.name,
            firstname: currentUser.firstname,
            lastname: currentUser.lastname,
            username: currentUser.username,
            profileImage: currentUser.profileImage,
            attendance: updated
        )
        user = currentUser
        isSaving = true
        defer { isSaving = false }

        do {
            let saved = try await service.updateAttendance(token: token, day: day, status: status, note: note)
            if var refreshedUser = user {
                var refreshed = refreshedUser.attendance
                refreshed[day] = saved
                refreshedUser = UserAttendanceUser(
                    userId: refreshedUser.userId,
                    name: refreshedUser.name,
                    firstname: refreshedUser.firstname,
                    lastname: refreshedUser.lastname,
                    username: refreshedUser.username,
                    profileImage: refreshedUser.profileImage,
                    attendance: refreshed
                )
                user = refreshedUser
            }
        } catch {
            if var rollbackUser = user {
                var rollback = rollbackUser.attendance
                rollback[day] = previous
                rollbackUser = UserAttendanceUser(
                    userId: rollbackUser.userId,
                    name: rollbackUser.name,
                    firstname: rollbackUser.firstname,
                    lastname: rollbackUser.lastname,
                    username: rollbackUser.username,
                    profileImage: rollbackUser.profileImage,
                    attendance: rollback
                )
                user = rollbackUser
            }
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

struct UserAttendanceView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = UserAttendanceViewModel()
    @State private var editingDay: String?
    @State private var selectedStatus = "P"
    @State private var noteText = ""
    @State private var showCalendar = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.user == nil {
                    ProgressView("Načítám docházku…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.user == nil {
                    ContentUnavailableView(
                        "Nepodařilo se načíst docházku",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                } else if let user = viewModel.user {
                    List {
                        Section {
                            monthSwitchRow
                        }

                        Section("Moje dny") {
                            ForEach(viewModel.days, id: \.self) { day in
                                dayRow(for: day, user: user)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                } else {
                    ContentUnavailableView(
                        "Žádná data",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Zkuste to prosím znovu.")
                    )
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Moje docházka")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCalendar = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Otevřít kalendář")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
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
            .sheet(isPresented: Binding(
                get: { editingDay != nil },
                set: { if !$0 { editingDay = nil } }
            )) {
                editSheet
            }
            .sheet(isPresented: $showCalendar) {
                CalendarView()
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

    private func dayRow(for day: String, user: UserAttendanceUser) -> some View {
        let entry = user.attendance[day]
        let status = normalizedStatus(entry?.status ?? "P")
        return Button {
            selectedStatus = status
            noteText = entry?.note ?? ""
            editingDay = day
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayTitle(day))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(daySubtitle(day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !(entry?.note?.isEmpty ?? true) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                }
                Text(statusLabel(status))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor(status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor(status).opacity(0.15))
                    .clipShape(Capsule())
                if viewModel.isSaving, editingDay == day {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var editSheet: some View {
        if let day = editingDay {
            NavigationStack {
                Form {
                    Section("Den") {
                        Text(dialogDate(day))
                    }
                    Section("Status") {
                        Picker("Status", selection: $selectedStatus) {
                            Text("Práce (P)").tag("P")
                            Text("Volno (V)").tag("V")
                            Text("Nemoc (N)").tag("N")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Poznámka") {
                        TextField("Volitelné", text: $noteText, axis: .vertical)
                            .lineLimit(1...4)
                    }
                }
                .navigationTitle("Upravit docházku")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Zrušit") {
                            editingDay = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Uložit") {
                            let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let normalizedNote = note.isEmpty ? nil : note
                            Task {
                                await viewModel.updateAttendance(
                                    token: authState.authToken,
                                    day: day,
                                    status: selectedStatus,
                                    note: normalizedNote
                                )
                                editingDay = nil
                            }
                        }
                        .disabled(viewModel.isSaving)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func normalizedStatus(_ raw: String) -> String {
        let value = raw.uppercased()
        return value == "D" ? "V" : value
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "P": return "Práce"
        case "V": return "Volno"
        case "N": return "Nemoc"
        default: return status
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "P": return .green
        case "V": return .blue
        case "N": return .red
        default: return .secondary
        }
    }

    private func dayTitle(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayTitleFormatter.string(from: date)
    }

    private func daySubtitle(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return "" }
        return Self.daySubtitleFormatter.string(from: date)
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

    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "EEEE d. M."
        return f
    }()

    private static let daySubtitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "yyyy"
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

#Preview {
    UserAttendanceView()
        .environmentObject(AuthState())
}
