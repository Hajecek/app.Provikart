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
                                .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        ForEach(viewModel.users) { user in
                            Section {
                                attendanceCard(for: user)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("Docházka")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
            .background(Color(uiColor: .systemGroupedBackground))
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
        }
        .padding(.horizontal, 16)
    }

    private func attendanceCard(for user: ManagerAttendanceUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(displayName(for: user))
                    .font(.headline)
                Spacer()
                Text(summaryText(for: user))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.days, id: \.self) { day in
                        let status = normalizedStatus(user.attendance[day]?.status ?? "?")
                        let note = user.attendance[day]?.note
                        VStack(spacing: 4) {
                            Text(shortDayLabel(day))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(status)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(statusTextColor(status))
                                .frame(width: 28, height: 28)
                                .background(statusBackground(status))
                                .clipShape(Circle())
                            if let note, !note.isEmpty {
                                Image(systemName: "text.bubble")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Color.clear
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        )
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

    private func summaryText(for user: ManagerAttendanceUser) -> String {
        let presentCount = viewModel.days.reduce(into: 0) { partial, day in
            let status = normalizedStatus(user.attendance[day]?.status ?? "")
            if status == "P" {
                partial += 1
            }
        }
        return "Přítomen \(presentCount)/\(viewModel.days.count)"
    }

    private func normalizedStatus(_ raw: String) -> String {
        let status = raw.uppercased()
        if status == "D" {
            return "V"
        }
        return status
    }

    private func shortDayLabel(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayShortFormatter.string(from: date)
    }

    private func statusBackground(_ status: String) -> Color {
        switch status.uppercased() {
        case "P":
            return Color.green.opacity(0.2)
        case "V":
            return Color.blue.opacity(0.2)
        case "N":
            return Color.red.opacity(0.2)
        case "O":
            return Color.orange.opacity(0.2)
        default:
            return Color.blue.opacity(0.2)
        }
    }

    private func statusTextColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "P":
            return .green
        case "V":
            return .blue
        case "N":
            return .red
        case "O":
            return .orange
        default:
            return .blue
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "d.M."
        return f
    }()
}

#Preview {
    ManagerAttendanceView()
        .environmentObject(AuthState())
}
