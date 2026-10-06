//
//  SalesLocalityPhotosSection.swift
//  Provikart
//
//  Foťák u rodinného domu. Snímek jde rovnou do sales_localities.photos.
//

import SwiftUI
import UIKit

@MainActor
final class RdPhotoShortcut: ObservableObject {
    @Published var localityId: Int?
    @Published var canAdd = false
    @Published private(set) var request = 0

    func bind(localityId: Int, canAdd: Bool) {
        self.localityId = localityId
        self.canAdd = canAdd
    }

    func clear(localityId: Int) {
        guard self.localityId == localityId else { return }
        self.localityId = nil
        self.canAdd = false
    }

    func requestCamera() {
        guard localityId != nil, canAdd else { return }
        request += 1
    }
}

struct SalesLocalityPhotosSection: View {
    let localityId: Int
    let token: String?
    let photos: [SalesLocalityPhoto]
    let photosMax: Int
    let onPhotosChanged: ([SalesLocalityPhoto]) -> Void

    @State private var showCamera = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var photoPendingDelete: SalesLocalityPhoto?

    private var limit: Int { max(photosMax, 1) }
    private var canAdd: Bool { photos.count < limit && !isUploading }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(photos.isEmpty ? "Zatím bez fotky" : "\(photos.count) z \(limit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isUploading {
                    ProgressView()
                }
            }

            if photos.isEmpty {
                Button(action: openCamera) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Vyfotit dům")
                            .font(.headline)
                        Text("Prázdný dům, nebo tam nikdo nebydlí.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(SalesLocalityKindStyle.rd)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(SalesLocalityKindStyle.rd.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            photoTile(photo)
                        }
                        if canAdd {
                            Button(action: openCamera) {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                        .font(.title3)
                                    Text("Další")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(SalesLocalityKindStyle.rd)
                                .frame(width: 108, height: 108)
                                .background(SalesLocalityKindStyle.rd.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showCamera) {
            CameraCapturePicker(
                onImage: { image in
                    showCamera = false
                    Task { await upload(image) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert("Smazat fotku?", isPresented: Binding(
            get: { photoPendingDelete != nil },
            set: { if !$0 { photoPendingDelete = nil } }
        )) {
            Button("Smazat", role: .destructive) {
                if let photo = photoPendingDelete {
                    photoPendingDelete = nil
                    Task { await delete(photo) }
                }
            }
            Button("Zrušit", role: .cancel) {
                photoPendingDelete = nil
            }
        } message: {
            Text("Fotka se z domu odstraní.")
        }
    }

    private func photoTile(_ photo: SalesLocalityPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: photo.url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    SalesLocalityKindStyle.rd.opacity(0.08)
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                photoPendingDelete = photo
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
            .padding(6)
            .accessibilityLabel("Smazat fotku")
        }
    }

    private func openCamera() {
        errorMessage = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "Na tomhle zařízení nejde otevřít foťák."
            return
        }
        showCamera = true
    }

    private func upload(_ image: UIImage) async {
        guard let jpeg = image.jpegDataFitting(maxBytes: 1_400_000) else {
            errorMessage = "Fotku se nepodařilo připravit."
            return
        }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            let updated = try await UserSalesLocalitiesService().uploadPhoto(
                token: token,
                localityId: localityId,
                jpeg: jpeg
            )
            onPhotosChanged(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ photo: SalesLocalityPhoto) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            let updated = try await UserSalesLocalitiesService().deletePhoto(token: token, file: photo.file)
            onPhotosChanged(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Foťák v liště drží celý detail, ne jen řádek s fotkou. Ten při scrollu z Formu zmizí
/// a dřív s ním zmizel i doplněk lišty.
struct RdPhotoDetailAccessory: ViewModifier {
    let localityId: Int
    let token: String?
    let photosCount: Int
    let photosMax: Int
    let isFamilyHouse: Bool
    let onPhotosChanged: ([SalesLocalityPhoto]) -> Void

    @EnvironmentObject private var shortcut: RdPhotoShortcut
    @State private var showCamera = false
    @State private var isUploading = false

    private var canAdd: Bool {
        photosCount < max(photosMax, 1) && !isUploading
    }

    func body(content: Content) -> some View {
        content
            .onAppear { publish() }
            .onChange(of: photosCount) { _, _ in publish() }
            .onChange(of: isUploading) { _, _ in publish() }
            .onChange(of: shortcut.request) { _, _ in
                guard isFamilyHouse, shortcut.localityId == localityId else { return }
                openCamera()
            }
            .onDisappear {
                guard isFamilyHouse else { return }
                shortcut.clear(localityId: localityId)
            }
            .sheet(isPresented: $showCamera) {
                CameraCapturePicker(
                    onImage: { image in
                        showCamera = false
                        Task { await upload(image) }
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
    }

    private func publish() {
        guard isFamilyHouse else { return }
        shortcut.bind(localityId: localityId, canAdd: canAdd)
    }

    private func openCamera() {
        guard canAdd, UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        showCamera = true
    }

    private func upload(_ image: UIImage) async {
        guard let jpeg = image.jpegDataFitting(maxBytes: 1_400_000) else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let updated = try await UserSalesLocalitiesService().uploadPhoto(
                token: token,
                localityId: localityId,
                jpeg: jpeg
            )
            onPhotosChanged(updated)
        } catch {
            showCamera = false
        }
    }
}

struct CameraCapturePicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapturePicker
        init(_ parent: CameraCapturePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

private extension UIImage {
    func jpegDataFitting(maxBytes: Int) -> Data? {
        let maxSide: CGFloat = 1600
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        var quality: CGFloat = 0.82
        var data = resized.jpegData(compressionQuality: quality)
        while let current = data, current.count > maxBytes, quality > 0.35 {
            quality -= 0.08
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }
}
