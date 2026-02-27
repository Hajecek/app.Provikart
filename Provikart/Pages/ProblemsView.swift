//
//  ProblemsView.swift
//  Provikart
//

import SwiftUI

enum ReportFilter: String, CaseIterable {
    case all = "Vše"
    case incomplete = "Nedokončené"
    case completed = "Dokončené"
}

struct ProblemsView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var reports: [UserReport] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var filter: ReportFilter = .incomplete

    private let reportsService = UserReportsService()

    private var filteredReports: [UserReport] {
        switch filter {
        case .all: return reports
        case .incomplete: return reports.filter { !$0.isCompleted }
        case .completed: return reports.filter(\.isCompleted)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !authState.isLoggedIn {
                    ContentUnavailableView(
                        "Problémy",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Pro zobrazení reportů se přihlaste.")
                    )
                } else if isLoading && reports.isEmpty {
                    ProgressView("Načítám reporty…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "Chyba",
                            systemImage: "exclamationmark.triangle",
                            description: Text(err)
                        )
                        Button("Zkusit znovu") {
                            Task { await loadReports() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if reports.isEmpty {
                    ContentUnavailableView(
                        "Žádné reporty",
                        systemImage: "doc.text",
                        description: Text("Zatím nemáte žádné reporty.")
                    )
                } else {
                    List {
                        Section {
                            Picker("Filtr", selection: $filter) {
                                ForEach(ReportFilter.allCases, id: \.self) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)

                        if filteredReports.isEmpty {
                            Section {
                                Text(filter == .all ? "Žádné reporty." : "V této kategorii žádné reporty.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            ForEach(filteredReports) { report in
                                Section {
                                    NavigationLink(value: report) {
                                        ReportRow(report: report)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .navigationDestination(for: UserReport.self) { report in
                        ReportDetailView(report: report)
                    }
                }
            }
            .scrollContentBackground(.visible)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Problémy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
            .refreshable {
                await loadReports()
            }
        }
        .task {
            await loadReports()
        }
    }

    private func loadReports() async {
        guard authState.isLoggedIn else {
            reports = []
            errorMessage = nil
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let token = await MainActor.run { authState.authToken }
        do {
            reports = try await reportsService.fetchUserReports(token: token)
        } catch {
            errorMessage = error.localizedDescription
            reports = []
        }
    }
}

// MARK: - Report row

private struct ReportRow: View {
    let report: UserReport

    private var statusColor: Color {
        switch (report.status ?? "").lowercased() {
        case "completed": return Color(uiColor: .systemGreen)
        case "created": return Color(uiColor: .systemOrange)
        case "open": return Color(uiColor: .systemYellow)
        default: return Color(uiColor: .tertiaryLabel)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let order = report.order_number, !order.isEmpty {
                        Text("Obj. č. \(order)")
                            .font(.subheadline.weight(.semibold))
                    }
                    if let status = report.status, !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
            if let note = report.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let userNote = report.user_note, !userNote.isEmpty {
                Text(userNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
                if let createdAt = report.created_at, !createdAt.isEmpty {
                    Text(formatDate(createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ dateString: String) -> String {
        // MySQL DATETIME např. "2025-02-27 14:30:00", nebo ISO8601
        let inFormatter = DateFormatter()
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        inFormatter.timeZone = TimeZone(identifier: "Europe/Prague")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            inFormatter.dateFormat = format
            if let date = inFormatter.date(from: dateString) {
                let out = DateFormatter()
                out.dateStyle = .short
                out.timeStyle = .short
                out.locale = Locale.current
                return out.string(from: date)
            }
        }
        return dateString
    }
}

// MARK: - Detail reportu

struct ReportDetailView: View {
    let report: UserReport

    var body: some View {
        List {
            Section("Základní údaje") {
                if let order = report.order_number, !order.isEmpty {
                    LabeledRow("Obj. číslo", order)
                }
                if let status = report.status, !status.isEmpty {
                    LabeledRow("Status", status)
                }
                LabeledRow("Dokončeno", report.isCompleted ? "Ano" : "Ne")
                if let created = report.created_at, !created.isEmpty {
                    LabeledRow("Vytvořeno", formatDate(created))
                }
                if let updated = report.updated_at, !updated.isEmpty {
                    LabeledRow("Upraveno", formatDate(updated))
                }
            }

            if let note = report.note, !note.isEmpty {
                Section("Poznámka") {
                    Text(note)
                }
            }
            if let userNote = report.user_note, !userNote.isEmpty {
                Section("Vaše poznámka") {
                    Text(userNote)
                }
            }
            if let statement = report.statement, !statement.isEmpty {
                Section("Výrok") {
                    Text(statement)
                }
            }
            if let statements = report.statements, !statements.isEmpty {
                Section("Výroky") {
                    ForEach(statements, id: \.self) { s in
                        Text(s)
                    }
                }
            }
            if let result = report.result, !result.isEmpty {
                Section("Výsledek") {
                    Text(result)
                }
            }
            if report.is_term_selection_issue {
                Section {
                    Label("Problém s výběrem termínu", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
            if report.created_by_manager == true {
                Section {
                    Label("Vytvořeno manažerem", systemImage: "person.badge.shield.checkmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(report.order_number.map { "Obj. \($0)" } ?? "Report #\(report.id)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ dateString: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        inFormatter.timeZone = TimeZone(identifier: "Europe/Prague")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            inFormatter.dateFormat = format
            if let date = inFormatter.date(from: dateString) {
                let out = DateFormatter()
                out.dateStyle = .medium
                out.timeStyle = .short
                out.locale = Locale.current
                return out.string(from: date)
            }
        }
        return dateString
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    ProblemsView()
        .environmentObject(AuthState())
}
