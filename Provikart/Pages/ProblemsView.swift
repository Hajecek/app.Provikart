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

// MARK: - ViewModel: vlastní pollovací Task, nezávislý na životnosti view – změny v DB se vždy projeví v UI

@MainActor
final class ProblemsViewModel: ObservableObject {
    @Published var reports: [UserReport] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    var getToken: (() -> String?)?
    private let service = UserReportsService()
    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        print("[Problems] ▶️ startPolling() – spouštím periodické načítání každých 5 s")
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await loadReports(silent: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await loadReports(silent: true)
            }
            print("[Problems] ⏹ pollování ukončeno")
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func loadReports(silent: Bool = false) async {
        guard let token = getToken?(), !token.isEmpty else {
            print("[Problems] ❌ Žádný token, přeskakuji načtení")
            reports = []
            errorMessage = nil
            isLoading = false
            return
        }
        if !silent {
            errorMessage = nil
            isLoading = true
        }
        let timeStr = { () -> String in
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: Date())
        }()
        print("[Problems] 🔄 \(timeStr) – načítám reporty z API…")
        do {
            let fetched = try await service.fetchUserReports(token: token)
            let orderNumbers = fetched.map { $0.order_number ?? "?" }.joined(separator: ", ")
            print("[Problems] ✅ \(timeStr) – načteno \(fetched.count) reportů: [\(orderNumbers)]")
            objectWillChange.send()
            reports = fetched
            isLoading = false
        } catch {
            print("[Problems] ❌ \(timeStr) – chyba: \(error.localizedDescription)")
            if !silent {
                errorMessage = error.localizedDescription
                reports = []
            }
            isLoading = false
        }
    }
}

// MARK: - View

struct ProblemsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ProblemsViewModel()
    @State private var filter: ReportFilter = .incomplete

    private var filteredReports: [UserReport] {
        switch filter {
        case .all: return viewModel.reports
        case .incomplete: return viewModel.reports.filter { !$0.isCompleted }
        case .completed: return viewModel.reports.filter(\.isCompleted)
        }
    }

    /// Mění se při změně dat z API – vynutí překreslení Listu (řeší „stejné id, starý obsah“).
    private var listContentId: String {
        viewModel.reports.map { "\($0.id)-\($0.order_number ?? "")-\($0.updated_at ?? "")" }.joined(separator: "|")
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
                } else if viewModel.isLoading && viewModel.reports.isEmpty {
                    ProgressView("Načítám reporty…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "Chyba",
                            systemImage: "exclamationmark.triangle",
                            description: Text(err)
                        )
                        Button("Zkusit znovu") {
                            Task { await viewModel.loadReports() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.reports.isEmpty {
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
                            ForEach(filteredReports, id: \.id) { report in
                                Section {
                                    NavigationLink(value: report) {
                                        ReportRow(report: report)
                                    }
                                }
                            }
                        }
                    }
                    .id(listContentId)
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
                await viewModel.loadReports()
            }
            .onAppear {
                viewModel.getToken = { [authState] in authState.authToken }
                if authState.isLoggedIn {
                    viewModel.startPolling()
                }
            }
            .onChange(of: authState.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    viewModel.startPolling()
                } else {
                    viewModel.stopPolling()
                    viewModel.reports = []
                }
            }
            .onDisappear {
                viewModel.stopPolling()
            }
        }
    }
}

// MARK: - Report row

private struct ReportRow: View {
    let report: UserReport

    private var statusColor: Color {
        if report.created_by_manager == true {
            return Color(uiColor: .systemBlue)
        }
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

// MARK: - Výroky jako timeline se svislou čárou (iOS styl)

private let timelineTrackWidth: CGFloat = 10
private let timelineLineWidth: CGFloat = 2
private let timelineDotSize: CGFloat = 8

private struct StatementsTimelineView: View {
    let statements: [ReportStatement]
    let formatDate: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(statements.enumerated()), id: \.offset) { index, s in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(s.is_result == true ? Color(uiColor: .systemGreen) : Color.accentColor)
                        .frame(width: timelineDotSize, height: timelineDotSize)
                        .frame(width: timelineTrackWidth, height: timelineTrackWidth, alignment: .center)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.text)
                            .font(.subheadline)
                        if let date = s.created_at, !date.isEmpty {
                            Text(formatDate(date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                let h = max(0, geo.size.height - 12)
                Rectangle()
                    .fill(Color(uiColor: .tertiaryLabel).opacity(0.4))
                    .frame(width: timelineLineWidth, height: h)
                    .offset(x: (timelineTrackWidth - timelineLineWidth) / 2, y: 6)
            }
            .frame(width: timelineTrackWidth, alignment: .leading)
        }
    }
}

// MARK: - Fotky reportu

private let reportImagesBaseURL = "https://provikart.cz/"

private struct ReportImagesView: View {
    let imagePaths: [String]

    @State private var fullScreenURL: IdentifiableURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(imagePaths.enumerated()), id: \.offset) { _, path in
                if let url = URL(string: path.hasPrefix("http") ? path : reportImagesBaseURL + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
                    ReportImageView(url: url) {
                        fullScreenURL = IdentifiableURL(url: url)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(item: $fullScreenURL) { item in
            FullScreenReportImageView(url: item.url) {
                fullScreenURL = nil
            }
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let id: String
    let url: URL
    init(url: URL) {
        self.url = url
        self.id = url.absoluteString
    }
}

private struct ReportImageView: View {
    let url: URL
    var onTap: (() -> Void)?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 160)
                    .overlay { ProgressView() }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            case .failure:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 80)
                    .overlay {
                        Label("Obrázek se nepodařilo načíst", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

private struct FullScreenReportImageView: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadedImage: UIImage?
    @State private var showShareSheet = false
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
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
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.5))
                    @unknown default:
                        EmptyView()
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
            .task(id: url) {
                await loadImageForShare()
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheetView(items: loadedImage != nil ? [loadedImage!] : [url])
            }
        }
    }

    private func loadImageForShare() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                await MainActor.run { loadedImage = img }
            }
        } catch {
            await MainActor.run { loadedImage = nil }
        }
    }
}

/// Otevře nativní iOS menu pro sdílení (uložit do Fotek, zkopírovat, atd.).
private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                    StatementsTimelineView(statements: statements, formatDate: formatDate)
                }
            }
            if let images = report.images, !images.isEmpty {
                Section("Fotky") {
                    ReportImagesView(imagePaths: images)
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
