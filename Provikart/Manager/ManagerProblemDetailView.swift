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

    var body: some View {
        List {
            Section("Základní údaje") {
                detailRow("Obj. číslo", report.order_number ?? "—")
                detailRow("Status", report.status ?? "—")
                detailRow("Dokončeno", report.isCompleted ? "Ano" : "Ne")
                if let created = report.created_at, !created.isEmpty {
                    detailRow("Vytvořeno", formatDate(created))
                }
                if let updated = report.updated_at, !updated.isEmpty {
                    detailRow("Upraveno", formatDate(updated))
                }
            }

            if let note = report.note, !note.isEmpty {
                Section("Popis problému") {
                    Text(note)
                }
            }

            if let statement = report.statement, !statement.isEmpty {
                Section("Výrok") {
                    Text(statement)
                }
            }

            if let statements = report.statements, !statements.isEmpty {
                Section("Historie výroků") {
                    ForEach(Array(statements.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                            if let createdAt = item.created_at, !createdAt.isEmpty {
                                Text(formatDate(createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let result = report.result, !result.isEmpty {
                Section("Výsledek") {
                    Text(result)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(report.order_number.map { "Obj. \($0)" } ?? "Report #\(report.id)")
        .navigationBarTitleDisplayMode(.inline)
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
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(identifier: "Europe/Prague")

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            input.dateFormat = format
            if let date = input.date(from: dateString) {
                let output = DateFormatter()
                output.locale = Locale(identifier: "cs_CZ")
                output.dateStyle = .medium
                output.timeStyle = .short
                return output.string(from: date)
            }
        }
        return dateString
    }
}
