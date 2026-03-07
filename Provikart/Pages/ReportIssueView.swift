//
//  ReportIssueView.swift
//  Provikart
//
//  Obrazovka pro nahlášení problému k objednávce. Podporuje obrázky (max 5) odesílané jako base64.
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ReportIssueView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

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
                        Text("Zadejte číslo objednávky z Moje O2.")
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
                            Label("Volitelná poznámka", systemImage: "note.text")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("Poznámka pro sebe nebo manažera…", text: $remark, axis: .vertical)
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
            .navigationTitle("Nahlásit problém")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                        dismiss()
                    } label: {
                        Image(systemName: "house")
                    }
                    .accessibilityLabel("Zpět na Domů")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Zrušit") {
                        isPresented = false
                        dismiss()
                    }
                    Spacer()
                    Button("Poslat") {
                        submitReport()
                    }
                    .fontWeight(.semibold)
                    .disabled(orderNumber.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .alert("Problém nahlášen", isPresented: $showSuccess) {
                Button("OK") {
                    showSuccess = false
                    isPresented = false
                    dismiss()
                }
            } message: {
                Text("Vaše nahlášení bylo odesláno.")
            }
        }
    }

    private func submitReport() {
        let order = orderNumber.trimmingCharacters(in: .whitespaces)
        let userNote = description.trimmingCharacters(in: .whitespaces)
        guard !order.isEmpty else { return }

        errorMessage = nil
        isSubmitting = true

        let remarkTrimmed = remark.trimmingCharacters(in: .whitespaces)

        Task { @MainActor in
            do {
                let imageDataUris = await loadSelectedImagesAsBase64()
                let payload = ReportIssuePayload(
                    order_number: order,
                    note: userNote.isEmpty ? nil : userNote,
                    user_note: remarkTrimmed.isEmpty ? nil : remarkTrimmed,
                    is_term_selection_issue: isTermSelectionIssue,
                    images: imageDataUris.isEmpty ? nil : imageDataUris
                )
                try await service.submitReport(payload: payload, token: authState.authToken)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    /// Načte vybrané fotky a vrátí pole řetězců "data:image/jpeg;base64,…". Max 2 obrázky, malá velikost,
    /// aby request nepřekročil QUIC/MTU limity („Message too long“).
    private func loadSelectedImagesAsBase64() async -> [String] {
        let maxSizePerImage = 200 * 1024 // 200 KB na obrázek, max 2 obrázky ≈ 400 KB celkem
        var result: [String] = []
        for item in selectedPhotoItems.prefix(2) {
            guard let loaded = try? await item.loadTransferable(type: ImageDataTransfer.self),
                  let data = loaded.jpegData(maxBytes: maxSizePerImage) else { continue }
            result.append("data:image/jpeg;base64,\(data.base64EncodedString())")
        }
        return result
    }
}

// MARK: - Načtení obrázku z PhotosPickerItem
private struct ImageDataTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImageDataTransfer(data: data)
        }
    }
}

extension ImageDataTransfer {
    /// Převod na JPEG s omezením velikosti. Obrázek se zmenší (max 1024 px) a zkomprimuje,
    /// aby celý request nepřekročil síťové limity („Message too long“ / connection lost).
    func jpegData(maxBytes: Int) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let resized = uiImage.resizedForUpload(maxLongEdge: 800)
        var quality: CGFloat = 0.4
        var result = resized.jpegData(compressionQuality: quality)
        while let data = result, data.count > maxBytes, quality > 0.15 {
            quality -= 0.05
            result = resized.jpegData(compressionQuality: quality)
        }
        return result
    }
}

extension UIImage {
    /// Zmenší obrázek tak, aby delší strana byla max `maxLongEdge` px (zachová poměr stran).
    fileprivate func resizedForUpload(maxLongEdge: CGFloat) -> UIImage {
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
    ReportIssueView(isPresented: .constant(true))
        .environmentObject(AuthState())
}
