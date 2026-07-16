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

    var monthTitle: String {
        Self.monthTitleFormatter.string(from: selectedMonthDate).capitalized
    }

    var todayKey: String {
        Self.dayKeyFormatter.string(from: Date())
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonthDate, equalTo: Date(), toGranularity: .month)
    }

    var todayStatus: String {
        guard let user else { return "?" }
        return normalizedStatus(user.attendance[todayKey]?.status ?? "?")
    }

    var todayNote: String? {
        let note = user?.attendance[todayKey]?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let note, !note.isEmpty else { return nil }
        return note
    }

    func statusCount(_ status: String) -> Int {
        guard let user else { return 0 }
        return days.reduce(into: 0) { count, day in
            if normalizedStatus(user.attendance[day]?.status ?? "") == status {
                count += 1
            }
        }
    }

    var notesCount: Int {
        guard let user else { return 0 }
        return days.reduce(into: 0) { count, day in
            let note = user.attendance[day]?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let note, !note.isEmpty {
                count += 1
            }
        }
    }

    var workRate: Double {
        guard !days.isEmpty else { return 0 }
        return Double(statusCount("P")) / Double(days.count)
    }

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
            isLoading = false
            guard !Self.isCancellation(error) else { return }
            if user == nil {
                days = []
                errorMessage = error.localizedDescription
            }
        }
    }

    func moveMonth(by offset: Int) {
        guard let updated = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) else { return }
        selectedMonthDate = updated
    }

    func jumpToCurrentMonth() {
        selectedMonthDate = Date()
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
            guard !Self.isCancellation(error) else { return }
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

    func normalizedStatus(_ raw: String) -> String {
        let value = raw.uppercased()
        if value == "D" { return "V" }
        return value
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
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

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
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
                    loadingView
                } else if let message = viewModel.errorMessage, viewModel.user == nil {
                    errorView(message)
                } else if let user = viewModel.user {
                    mainContent(user: user)
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
            .navigationBarTitleDisplayMode(.inline)
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

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Načítám docházku…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst docházku", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Zkusit znovu") {
                Task {
                    await viewModel.loadAttendance(token: authState.authToken)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func mainContent(user: UserAttendanceUser) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    monthNavigationCard
                    summaryHeroCard
                    statusLegend
                    daysSection(user: user)
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
            .onAppear {
                scrollToToday(proxy: proxy)
            }
            .onChange(of: viewModel.days) { _, _ in
                scrollToToday(proxy: proxy)
            }
        }
    }

    private func scrollToToday(proxy: ScrollViewProxy) {
        guard viewModel.isCurrentMonth, viewModel.days.contains(viewModel.todayKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.snappy(duration: 0.35)) {
                proxy.scrollTo(viewModel.todayKey, anchor: .center)
            }
        }
    }

    private var monthNavigationCard: some View {
        HStack(spacing: 12) {
            monthStepButton(systemName: "chevron.left") {
                viewModel.moveMonth(by: -1)
            }

            VStack(spacing: 2) {
                Text(viewModel.monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text("\(viewModel.days.count) dní v přehledu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            monthStepButton(systemName: "chevron.right") {
                viewModel.moveMonth(by: 1)
            }

            if !viewModel.isCurrentMonth {
                Button("Dnes") {
                    viewModel.jumpToCurrentMonth()
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
        let todayStatus = viewModel.todayStatus
        let todayColor = statusColor(todayStatus)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                workRateRing

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.isCurrentMonth ? "Dnes" : "Souhrn měsíce")
                        .font(.headline)

                    if viewModel.isCurrentMonth {
                        HStack(spacing: 8) {
                            Text(statusLabel(todayStatus))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(todayColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(todayColor.opacity(0.14), in: Capsule())

                            if viewModel.todayNote != nil {
                                Image(systemName: "text.bubble.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let note = viewModel.todayNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("Klepnutím na den upravíte status nebo poznámku.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Přehled vaší docházky za vybraný měsíc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().opacity(0.35)

            HStack(spacing: 8) {
                monthMetricChip(status: "P", title: "Práce", count: viewModel.statusCount("P"), color: .green)
                monthMetricChip(status: "V", title: "Volno", count: viewModel.statusCount("V"), color: .blue)
                monthMetricChip(status: "N", title: "Nemoc", count: viewModel.statusCount("N"), color: .red)
            }

            if viewModel.notesCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.notesCount) \(notesWord(viewModel.notesCount)) v tomto měsíci")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardBackground(tint: todayColor == .secondary ? .green : todayColor))
    }

    private var workRateRing: some View {
        let rate = viewModel.workRate
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
                Text("práce")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Podíl práce \(percentage) procent")
    }

    private func monthMetricChip(status: String, title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(status)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: Circle())
            Text("\(count)")
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusLegend: some View {
        HStack(spacing: 12) {
            legendItem(status: "P", title: "Práce", color: .green)
            legendItem(status: "V", title: "Volno", color: .blue)
            legendItem(status: "N", title: "Nemoc", color: .red)
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(status: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func daysSection(user: UserAttendanceUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Moje dny")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(viewModel.days.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 10) {
                ForEach(viewModel.days, id: \.self) { day in
                    dayCard(for: day, user: user)
                        .id(day)
                }
            }
        }
    }

    private func dayCard(for day: String, user: UserAttendanceUser) -> some View {
        let entry = user.attendance[day]
        let status = viewModel.normalizedStatus(entry?.status ?? "P")
        let color = statusColor(status)
        let note = entry?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !(note?.isEmpty ?? true)
        let isToday = day == viewModel.todayKey

        return Button {
            selectedStatus = status
            noteText = entry?.note ?? ""
            editingDay = day
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(weekdayShort(day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                        .textCase(.uppercase)
                    Text(dayNumber(day))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                }
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(weekdayFull(day))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if isToday {
                            Text("Dnes")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }

                    if hasNote, let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(statusSubtitle(status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(status)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .frame(width: 34, height: 34)
                        .background(color.opacity(0.14), in: Circle())

                    if viewModel.isSaving, editingDay == day {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if hasNote {
                        Image(systemName: "text.bubble.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(cardBackground(tint: isToday ? Color.accentColor : color))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.28), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(weekdayFull(day)) \(dayNumber(day))., \(statusLabel(status))")
    }

    @ViewBuilder
    private var editSheet: some View {
        if let day = editingDay {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dialogDate(day))
                                .font(.title2.weight(.bold))
                            Text(weekdayFull(day))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(cardBackground(tint: statusColor(selectedStatus)))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Status")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                statusPickButton(status: "P", title: "Práce", icon: "briefcase.fill")
                                statusPickButton(status: "V", title: "Volno", icon: "sun.max.fill")
                                statusPickButton(status: "N", title: "Nemoc", icon: "cross.case.fill")
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Poznámka")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("Volitelná poznámka k dni", text: $noteText, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                )
                        }
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
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
                        .fontWeight(.semibold)
                        .disabled(viewModel.isSaving)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func statusPickButton(status: String, title: String, icon: String) -> some View {
        let isSelected = selectedStatus == status
        let color = statusColor(status)

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedStatus = status
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(status)
                    .font(.caption2.weight(.bold))
                    .opacity(0.8)
            }
            .foregroundStyle(isSelected ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? color : color.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func monthStepButton(systemName: String, action: @escaping () -> Void) -> some View {
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

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "P": return "Práce"
        case "V": return "Volno"
        case "N": return "Nemoc"
        default: return status
        }
    }

    private func statusSubtitle(_ status: String) -> String {
        switch status {
        case "P": return "Pracovní den"
        case "V": return "Den volna"
        case "N": return "Nemocenská"
        default: return "Bez statusu"
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

    private func notesWord(_ count: Int) -> String {
        switch count {
        case 1: return "poznámka"
        case 2...4: return "poznámky"
        default: return "poznámek"
        }
    }

    private func weekdayFull(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        let raw = Self.weekdayFullFormatter.string(from: date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private func dayNumber(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayNumberFormatter.string(from: date)
    }

    private func weekdayShort(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return "" }
        return Self.weekdayShortFormatter.string(from: date)
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

    private static let weekdayFullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "EEEE"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "d"
        return f
    }()

    private static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "EE"
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
