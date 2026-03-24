//
//  ManagerProblemDetailView.swift
//  Provikart
//
//  Samostatný detail reportu pro manažera.
//

import SwiftUI

struct ManagerProblemDetailView: View {
    let report: UserReport
    @Binding var selectedReport: UserReport?
    @EnvironmentObject private var authState: AuthState
    @State private var showReplySheet = false
    @State private var refreshedReport: UserReport?
    private let managerReportsService = ManagerReportsService()

    private var currentReport: UserReport {
        refreshedReport ?? report
    }

    var body: some View {
        List {
            Section("Základní údaje") {
                detailRow("Obj. číslo", currentReport.order_number ?? "—")
                detailRow("Stav", currentReport.statusDisplayCzech)
                detailRow("Dokončeno", currentReport.isCompleted ? "Ano" : "Ne")
                if let created = currentReport.created_at, !created.isEmpty {
                    detailRow("Vytvořeno", formatDate(created))
                }
                if let updated = currentReport.updated_at, !updated.isEmpty {
                    detailRow("Upraveno", formatDate(updated))
                }
            }

            if let note = currentReport.note, !note.isEmpty {
                Section("Popis problému") {
                    Text(note)
                }
            }

            if let statements = currentReport.statements, !statements.isEmpty {
                Section("Historie výroků") {
                    ManagerStatementsTimelineView(statements: statements, formatDate: formatDate)
                }
            }

            if let result = currentReport.result, !result.isEmpty {
                Section("Výsledek") {
                    Text(result)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentReport.order_number.map { "Obj. \($0)" } ?? "Report #\(currentReport.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReplySheet = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                }
            }
        }
        .sheet(isPresented: $showReplySheet) {
            ManagerReplyToReportView(report: currentReport) {
                showReplySheet = false
                Task { await refreshReport() }
            }
            .environmentObject(authState)
        }
        .onDisappear {
            selectedReport = nil
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDate(_ dateString: String) -> String {
        ReportDatePresentation.formatDetail(dateString)
    }

    private func refreshReport() async {
        guard let token = authState.authToken, !token.isEmpty else { return }
        do {
            let reports = try await managerReportsService.fetchManagerReports(token: token)
            guard let updated = reports.first(where: { $0.id == report.id }) else { return }
            refreshedReport = updated
            selectedReport = updated
        } catch {
            // Tiché selhání - detail zůstane na posledních dostupných datech.
        }
    }
}

private let managerTimelineTrackWidth: CGFloat = 10
private let managerTimelineLineWidth: CGFloat = 2
private let managerTimelineDotSize: CGFloat = 8

private struct ManagerStatementsTimelineView: View {
    let statements: [ReportStatement]
    let formatDate: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(statements.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(item.is_result == true ? Color(uiColor: .systemGreen) : Color.accentColor)
                        .frame(width: managerTimelineDotSize, height: managerTimelineDotSize)
                        .frame(width: managerTimelineTrackWidth, height: managerTimelineTrackWidth, alignment: .center)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .font(.subheadline)
                        if let createdAt = item.created_at, !createdAt.isEmpty {
                            Text(formatDate(createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, index < statements.count - 1 ? 16 : 0)
                }
            }
        }
        .padding(.vertical, 8)
        .background(alignment: .leading) {
            GeometryReader { geo in
                let lineHeight = max(0, geo.size.height - 12)
                Rectangle()
                    .fill(Color(uiColor: .tertiaryLabel).opacity(0.4))
                    .frame(width: managerTimelineLineWidth, height: lineHeight)
                    .offset(x: (managerTimelineTrackWidth - managerTimelineLineWidth) / 2, y: 6)
            }
            .frame(width: managerTimelineTrackWidth, alignment: .leading)
        }
    }
}

private struct ManagerReplyToReportView: View {
    let report: UserReport
    var onSaved: () -> Void
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var statement: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let updateService = ReportUpdateService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Napište odpověď…", text: $statement, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("Odpověď")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Odpověď")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zrušit") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Odeslat") {
                        submitReply()
                    }
                    .disabled(statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .alert("Odesláno", isPresented: $showSuccess) {
                Button("OK") {
                    onSaved()
                    dismiss()
                }
            } message: {
                Text("Odpověď byla uložena.")
            }
        }
    }

    private func submitReply() {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isSaving = true

        Task { @MainActor in
            do {
                let payload = ReportUpdatePayload(
                    id: report.id,
                    statement: trimmed
                )
                try await updateService.updateManagerReport(payload: payload, token: authState.authToken)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
