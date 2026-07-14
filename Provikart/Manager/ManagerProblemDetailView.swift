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
            if let note = currentReport.note, !note.isEmpty {
                Section {
                    ReportProblemDetailCard(text: note)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 20, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("Základní údaje") {
                if currentReport.is_deferred_sale_issue {
                    detailRow("Typ", currentReport.issue_type_label ?? "Odložený prodej")
                } else if let issueLabel = currentReport.issue_type_label, !issueLabel.isEmpty {
                    detailRow("Typ", issueLabel)
                }
                if !currentReport.is_deferred_sale_issue {
                    detailRow("Obj. číslo", currentReport.order_number ?? "—")
                }
                detailRow("Stav", currentReport.statusDisplayCzech)
                detailRow("Dokončeno", currentReport.isCompleted ? "Ano" : "Ne")
                if let created = currentReport.created_at, !created.isEmpty {
                    detailRow("Vytvořeno", formatDate(created))
                }
                if let updated = currentReport.updated_at, !updated.isEmpty {
                    detailRow("Upraveno", formatDate(updated))
                }
            }

            if let statements = currentReport.statements, !statements.isEmpty {
                Section("Historie vývoje") {
                    ManagerStatementsTimelineView(statements: statements, formatDate: formatDate)
                }
            }

            if let images = currentReport.images, !images.isEmpty {
                Section("Fotky") {
                    ManagerReportImagesView(imagePaths: images, authToken: authState.authToken)
                }
            }

            if let result = currentReport.result, !result.isEmpty {
                Section("Výsledek") {
                    Text(result)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentReport.managerDetailTitle)
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
            let result = try await managerReportsService.fetchManagerReports(
                token: token,
                filter: currentReport.managerReportsFilter
            )
            guard let updated = result.reports.first(where: { $0.id == report.id }) else { return }
            refreshedReport = updated
            selectedReport = updated
        } catch {
            // Tiché selhání - detail zůstane na posledních dostupných datech.
        }
    }
}

private let managerReportImagesBaseURL = "https://provikart.cz/"

private struct ManagerReportImagesView: View {
    let imagePaths: [String]
    var authToken: String?
    @State private var fullScreenURL: ManagerIdentifiableURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(imagePaths.enumerated()), id: \.offset) { _, path in
                if let url = resolvedImageURL(for: path) {
                    ReportAttachmentThumbnailView(url: url, token: authToken) {
                        fullScreenURL = ManagerIdentifiableURL(url: url)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(item: $fullScreenURL) { item in
            ManagerFullScreenReportImageView(url: item.url, authToken: authToken) {
                fullScreenURL = nil
            }
        }
    }

    private func resolvedImageURL(for rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? trimmed
            return URL(string: encoded)
        }

        let relative = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return nil }

        if relative.contains("?") {
            let parts = relative.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let path = String(parts[0])
            let query = parts.count > 1 ? String(parts[1]) : ""

            var components = URLComponents()
            components.scheme = "https"
            components.host = "provikart.cz"
            components.percentEncodedPath = "/" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            components.percentEncodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            return components.url
        }

        let encodedPath = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        return URL(string: managerReportImagesBaseURL + encodedPath)
    }
}

private struct ManagerIdentifiableURL: Identifiable {
    let id: String
    let url: URL

    init(url: URL) {
        self.url = url
        self.id = url.absoluteString
    }
}

private struct ManagerFullScreenReportImageView: View {
    let url: URL
    var authToken: String?
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadedImage: UIImage?
    @State private var showShareSheet = false
    @State private var loadFailed = false
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if let loadedImage {
                        Image(uiImage: loadedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        scale = min(max(newScale, minScale), maxScale)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                    } else if loadFailed {
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.5))
                            Button("Zkusit znovu") {
                                Task { await loadImage() }
                            }
                            .tint(.white)
                        }
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .task(id: "\(url.absoluteString)|\(authToken ?? "")") {
                await loadImage()
            }
            .sheet(isPresented: $showShareSheet) {
                ManagerShareSheetView(items: loadedImage != nil ? [loadedImage!] : [url])
            }
        }
    }

    private func loadImage() async {
        await MainActor.run {
            loadFailed = false
            loadedImage = nil
        }
        let img = await ReportAttachmentImageLoader.loadUIImage(from: url, token: authToken)
        await MainActor.run {
            loadedImage = img
            loadFailed = (img == nil)
        }
    }
}

private struct ManagerShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
