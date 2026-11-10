//
//  PerformanceDayReportView.swift
//  Provikart
//

import SwiftUI

struct PerformanceDayReportView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void = {}

    @State private var knocked = ""
    @State private var opened = ""
    @State private var comment = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let minChars = 50

    private var charCount: Int {
        comment.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Za dnešek nemáš žádnou službu. Napiš, kolik lidí jsi naklepal, kolik otevřelo a pár řádků, proč se nepodařilo prodat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    countField(title: "Naklepal", text: $knocked)
                    countField(title: "Otevřelo", text: $opened)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Komentář")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Proč se nepodařilo prodat", text: $comment, axis: .vertical)
                        .lineLimit(5...10)
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("\(charCount) / \(minChars) znaků")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(charCount >= minChars ? Color.green : Color.orange)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(isSaving ? "Ukládám…" : "Uložit report")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Report výkonu")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: knocked) { _, value in
            knocked = digits(value)
        }
        .onChange(of: opened) { _, value in
            opened = digits(value)
        }
    }

    private func countField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func digits(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(4))
    }

    private func save() async {
        let knockedCount = Int(knocked) ?? -1
        let openedCount = Int(opened) ?? -1
        if openedCount > knockedCount {
            errorMessage = "Otevřených nemůže být víc než naklepaných."
            return
        }
        if charCount < minChars {
            errorMessage = "Komentář musí mít aspoň 50 znaků."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await PerformanceDayReportService().save(
                token: authState.authToken,
                knocked: knockedCount,
                opened: openedCount,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
