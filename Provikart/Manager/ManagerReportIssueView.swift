//
//  ManagerReportIssueView.swift
//  Provikart
//
//  Manažerská varianta nahlášení problému.
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private struct TeamMember: Identifiable, Hashable {
    let userId: Int?
    let username: String?
    let fullName: String?

    var id: String {
        if let userId { return "id-\(userId)" }
        if let username, !username.isEmpty { return "u-\(username.lowercased())" }
        if let fullName, !fullName.isEmpty { return "n-\(fullName.lowercased())" }
        return "unknown"
    }

    var displayLabel: String {
        if let fullName, !fullName.isEmpty, let username, !username.isEmpty {
            return "\(fullName) (@\(username))"
        }
        if let fullName, !fullName.isEmpty { return fullName }
        if let username, !username.isEmpty { return "@\(username)" }
        if let userId { return "Uživatel #\(userId)" }
        return "Neznámý uživatel"
    }
}

struct ManagerReportIssueView: View {
    @Binding var isPresented: Bool
    @ObservedObject var authState: AuthState
    let isModalPresentation: Bool
    var onClose: (() -> Void)? = nil

    @State private var orderNumber = ""
    @State private var description = ""
    @State private var remark = ""
    @State private var isTermSelectionIssue = false
    @State private var teamMembers: [TeamMember] = []
    @State private var selectedMemberId: TeamMember.ID?
    @State private var isLoadingTeamMembers = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let service = ReportIssueService()
    private let managerTeamMembersService = ManagerTeamMembersService()
    private let managerReportsService = ManagerReportsService()
    private var selectedMember: TeamMember? {
        guard let selectedMemberId else { return nil }
        return teamMembers.first(where: { $0.id == selectedMemberId })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                Form {
                    Section {
                        if isLoadingTeamMembers {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Načítám členy týmu…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if teamMembers.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Členové týmu nebyli načteni.")
                                    .foregroundStyle(.secondary)
                                Button("Načíst znovu") {
                                    Task { await loadTeamMembers(forceReload: true) }
                                }
                            }
                        } else {
                            Picker("Komu report patří", selection: Binding(
                                get: { selectedMemberId },
                                set: { selectedMemberId = $0 }
                            )) {
                                Text("Vyberte člena týmu").tag(Optional<TeamMember.ID>.none)
                                ForEach(teamMembers) { member in
                                    Text(member.displayLabel).tag(Optional(member.id))
                                }
                            }
                        }
                    } header: {
                        Text("Člen týmu")
                    } footer: {
                        Text("Vyberte, pro kterého člena týmu report vytváříte.")
                    }

                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "number.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            TextField("Např. O7MQ8Z82", text: $orderNumber)
                                .textContentType(.none)
                                .keyboardType(.asciiCapable)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text("Číslo objednávky")
                    } footer: {
                        Text("Zadejte číslo objednávky člena týmu.")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Co je problém?", systemImage: "text.alignleft")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("Popište problém k objednávce…", text: $description, axis: .vertical)
                                .lineLimit(4...10)
                                .textFieldStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Popis problému")
                    } footer: {
                        Text("Hlavní popis bude uložen k reportu.")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Poznámka pro tým", systemImage: "note.text")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("Volitelná interní poznámka…", text: $remark, axis: .vertical)
                                .lineLimit(2...6)
                                .textFieldStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Poznámka")
                    }

                    Section {
                        Toggle(isOn: $isTermSelectionIssue) {
                            Label("Jen problém s výběrem termínu", systemImage: "calendar.badge.clock")
                        }
                        .tint(.accentColor)
                    } header: {
                        Text("Typ problému")
                    } footer: {
                        Text("Zaškrtněte, pokud jde pouze o nemožnost nebo potíže s výběrem termínu instalace.")
                    }

                    Section {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 2,
                            matching: .images
                        ) {
                            Label("Přidat fotky", systemImage: "photo.on.rectangle.angled")
                        }
                        if !selectedPhotoItems.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Vybráno \(selectedPhotoItems.count) \(selectedPhotoItems.count == 1 ? "fotka" : "fotek")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Přílohy")
                    } footer: {
                        Text("Max. 2 fotky (kvůli spolehlivému odeslání přes mobilní síť).")
                    }

                    if let errorMessage {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Poslat report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        if isModalPresentation {
                            isPresented = false
                        } else {
                            onClose?()
                        }
                    } label: {
                        Image(systemName: isModalPresentation ? "xmark" : "house")
                    }
                    .accessibilityLabel(isModalPresentation ? "Zavřít" : "Zpět na Domů")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ProfileBarButton()
                        .environmentObject(authState)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if isModalPresentation {
                        Button("Zrušit") {
                            isPresented = false
                        }
                    } else {
                        Button {
                            onClose?()
                        } label: {
                            Image(systemName: "house")
                        }
                        .accessibilityLabel("Zpět na Domů")

                        Button("Vyčistit") {
                            resetForm()
                        }
                    }
                    Spacer()
                    submitButton
                }
            }
            .toolbar(!isModalPresentation ? .hidden : .visible, for: .tabBar)
            .task {
                await loadTeamMembers(forceReload: false)
            }
            .alert("Problém nahlášen", isPresented: $showSuccess) {
                Button("OK") {
                    showSuccess = false
                    if isModalPresentation {
                        isPresented = false
                    } else {
                        resetForm()
                    }
                }
            } message: {
                Text("Nahlášení manažera bylo odesláno.")
            }
        }
    }

    private func submitReport() {
        guard let selectedMember else {
            errorMessage = "Vyberte člena týmu."
            return
        }
        let order = orderNumber.trimmingCharacters(in: .whitespaces)
        let issueText = description.trimmingCharacters(in: .whitespaces)
        guard !order.isEmpty else { return }

        errorMessage = nil
        isSubmitting = true
        let remarkTrimmed = remark.trimmingCharacters(in: .whitespaces)

        Task { @MainActor in
            do {
                let imageDataUris = await loadSelectedImagesAsBase64()
                let payload = ReportIssuePayload(
                    order_number: order,
                    note: issueText.isEmpty ? nil : issueText,
                    user_note: remarkTrimmed.isEmpty ? nil : remarkTrimmed,
                    is_term_selection_issue: isTermSelectionIssue,
                    user_id: selectedMember.userId,
                    username: selectedMember.username,
                    images: imageDataUris.isEmpty ? nil : imageDataUris
                )
                try await service.submitReport(payload: payload, token: authState.authToken)
                showSuccess = true
            } catch is CancellationError {
                // Zavření view během odesílání není uživatelská chyba.
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func loadTeamMembers(forceReload: Bool) async {
        if !forceReload && !teamMembers.isEmpty { return }
        await MainActor.run {
            isLoadingTeamMembers = true
        }
        do {
            let apiMembers = try await managerTeamMembersService.fetchMembers(token: authState.authToken)
            var mappedMembers = buildTeamMembers(from: apiMembers)
            // Fallback: když endpoint vrátí prázdno, zkusíme aspoň známé členy z manager reportů.
            if mappedMembers.isEmpty {
                let reports = try? await managerReportsService.fetchManagerReports(token: authState.authToken)
                if let reports {
                    mappedMembers = buildTeamMembersFromReports(reports)
                }
            }
            await MainActor.run {
                teamMembers = mappedMembers
                if selectedMemberId == nil {
                    selectedMemberId = mappedMembers.first?.id
                }
                isLoadingTeamMembers = false
            }
        } catch {
            let reports = try? await managerReportsService.fetchManagerReports(token: authState.authToken)
            let fallbackMembers = reports.map(buildTeamMembersFromReports) ?? []
            await MainActor.run {
                if !fallbackMembers.isEmpty {
                    teamMembers = fallbackMembers
                    if selectedMemberId == nil {
                        selectedMemberId = fallbackMembers.first?.id
                    }
                }
                if errorMessage == nil {
                    errorMessage = "Nepodařilo se načíst členy týmu z API."
                }
                isLoadingTeamMembers = false
            }
        }
    }

    private func buildTeamMembers(from members: [ManagerTeamMember]) -> [TeamMember] {
        members.map {
            TeamMember(
                userId: $0.id,
                username: $0.username?.trimmingCharacters(in: .whitespacesAndNewlines),
                fullName: $0.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.sorted {
            $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending
        }
    }

    private func buildTeamMembersFromReports(_ reports: [UserReport]) -> [TeamMember] {
        var byKey: [String: TeamMember] = [:]
        for report in reports where report.created_by_manager != true {
            let username = report.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fullName = report.user_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let userId = report.user_id
            let key: String
            if let userId {
                key = "id-\(userId)"
            } else if let username, !username.isEmpty {
                key = "u-\(username.lowercased())"
            } else {
                continue
            }
            if byKey[key] == nil {
                byKey[key] = TeamMember(userId: userId, username: username, fullName: fullName)
            }
        }
        return byKey.values.sorted {
            $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending
        }
    }

    private func loadSelectedImagesAsBase64() async -> [String] {
        let maxSizePerImage = 200 * 1024
        var result: [String] = []
        for item in selectedPhotoItems.prefix(2) {
            guard let loaded = try? await item.loadTransferable(type: ManagerImageDataTransfer.self),
                  let data = loaded.jpegData(maxBytes: maxSizePerImage) else { continue }
            result.append("data:image/jpeg;base64,\(data.base64EncodedString())")
        }
        return result
    }

    private var submitButton: some View {
        Button {
            submitReport()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Poslat")
            }
            .frame(minWidth: 72)
        }
        .fontWeight(.semibold)
        .disabled(
            selectedMemberId == nil ||
            orderNumber.trimmingCharacters(in: .whitespaces).isEmpty ||
            description.trimmingCharacters(in: .whitespaces).isEmpty ||
            isSubmitting
        )
    }

    private func resetForm() {
        if let first = teamMembers.first {
            selectedMemberId = first.id
        } else {
            selectedMemberId = nil
        }
        orderNumber = ""
        description = ""
        remark = ""
        isTermSelectionIssue = false
        selectedPhotoItems = []
        errorMessage = nil
        isSubmitting = false
    }
}

private struct ManagerImageDataTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ManagerImageDataTransfer(data: data)
        }
    }
}

private extension ManagerImageDataTransfer {
    func jpegData(maxBytes: Int) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let resized = uiImage.resizedForManagerUpload(maxLongEdge: 800)
        var quality: CGFloat = 0.4
        var result = resized.jpegData(compressionQuality: quality)
        while let data = result, data.count > maxBytes, quality > 0.15 {
            quality -= 0.05
            result = resized.jpegData(compressionQuality: quality)
        }
        return result
    }
}

private extension UIImage {
    func resizedForManagerUpload(maxLongEdge: CGFloat) -> UIImage {
        let size = self.size
        guard size.width > maxLongEdge || size.height > maxLongEdge else { return self }
        let ratio = min(maxLongEdge / size.width, maxLongEdge / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

#Preview {
    ManagerReportIssueView(isPresented: .constant(true), authState: AuthState(), isModalPresentation: true)
}
