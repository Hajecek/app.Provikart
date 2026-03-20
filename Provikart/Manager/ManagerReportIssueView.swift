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

struct ManagerReportIssueView: View {
    @Binding var isPresented: Bool
    @ObservedObject var authState: AuthState
    let isModalPresentation: Bool
    var onClose: (() -> Void)? = nil

    @State private var orderNumber = ""
    @State private var description = ""
    @State private var remark = ""
    @State private var isTermSelectionIssue = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let service = ReportIssueService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                Form {
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
            orderNumber.trimmingCharacters(in: .whitespaces).isEmpty ||
            description.trimmingCharacters(in: .whitespaces).isEmpty ||
            isSubmitting
        )
    }

    private func resetForm() {
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
