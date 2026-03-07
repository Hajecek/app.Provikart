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
                        TextField("Číslo objednávky", text: $orderNumber)
                            .textContentType(.none)
                            .keyboardType(.numberPad)

                        TextField("Popis problému", text: $description, axis: .vertical)
                            .lineLimit(3...8)

                        TextField("Poznámka", text: $remark, axis: .vertical)
                            .lineLimit(2...6)

                        Toggle(isOn: $isTermSelectionIssue) {
                            Text("Jen problém s výběrem termínu")
                        }
                    } header: {
                        Text("Údaje")
                    } footer: {
                        Text("Zaškrtněte, pokud jde pouze o nemožnost nebo potíže s výběrem termínu instalace.")
                    }

                    Section {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 5,
                            matching: .images
                        ) {
                            Label("Přidat fotky", systemImage: "photo.on.rectangle.angled")
                        }
                        if !selectedPhotoItems.isEmpty {
                            Text("Vybráno \(selectedPhotoItems.count) \(selectedPhotoItems.count == 1 ? "fotek" : "fotek")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Obrázky")
                    } footer: {
                        Text("Volitelně až 5 fotek. Obrázky se zmenší a zkomprimují kvůli odeslání (max. cca 800 KB každý).")
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
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
                    Button {
                        isPresented = false
                        dismiss()
                    } label: {
                        Label("Zrušit", systemImage: "xmark.circle")
                    }
                    Spacer()
                    Button {
                        submitReport()
                    } label: {
                        Label("Odeslat", systemImage: "paperplane.fill")
                    }
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

    /// Načte vybrané fotky a vrátí pole řetězců "data:image/jpeg;base64,…". Obrázky se zmenší a zkomprimují,
    /// aby request nepřekročil síťové limity („Message too long“).
    private func loadSelectedImagesAsBase64() async -> [String] {
        let maxSizePerImage = 800 * 1024 // 800 KB na obrázek (5× ≈ 4 MB celkem)
        var result: [String] = []
        for item in selectedPhotoItems.prefix(5) {
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
    /// Převod na JPEG s omezením velikosti. Obrázek se zmenší (max 1200 px) a zkomprimuje,
    /// aby celý request nepřekročil síťové limity („Message too long“ / MTU).
    func jpegData(maxBytes: Int) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let resized = uiImage.resizedForUpload(maxLongEdge: 1200)
        var quality: CGFloat = 0.6
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
