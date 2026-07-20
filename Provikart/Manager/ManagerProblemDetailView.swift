//
//  ManagerProblemDetailView.swift
//  Provikart
//
//  Samostatný detail reportu pro manažera.
//

import SwiftUI

// MARK: - Sdílený vzhled se seznamem

private enum ManagerReportAppearance {
    enum Status: Int, CaseIterable {
        case created = 0, open, completed

        var label: String {
            switch self {
            case .created: return "Nové"
            case .open: return "Probíhá"
            case .completed: return "Hotovo"
            }
        }

        var icon: String {
            switch self {
            case .created: return "sparkles"
            case .open: return "arrow.triangle.2.circlepath"
            case .completed: return "checkmark.circle.fill"
            }
        }
    }

    static func status(for report: UserReport) -> Status {
        switch (report.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "created": return .created
        case "open": return .open
        case "completed": return .completed
        default: return .created
        }
    }

    static func accentColor(for report: UserReport) -> Color {
        if report.is_deferred_sale_issue { return .purple }
        if report.is_incomplete_order_issue { return .red }
        if report.is_term_selection_issue { return .blue }
        if report.created_by_manager == true { return .blue }
        switch status(for: report) {
        case .created: return .orange
        case .open: return .yellow
        case .completed: return .green
        }
    }

    static func headerTint(for report: UserReport) -> Color {
        let accent = accentColor(for: report)
        return accent == .yellow ? .orange : accent
    }

    static func rowIcon(for report: UserReport) -> String {
        if report.is_deferred_sale_issue { return "clock.arrow.circlepath" }
        if report.is_incomplete_order_issue { return "cart.badge.minus" }
        if report.is_term_selection_issue { return "calendar.badge.exclamationmark" }
        if report.created_by_manager == true { return "person.2.badge.gearshape.fill" }
        return "person.crop.circle.badge.exclamationmark"
    }

    static func directionLabel(for report: UserReport) -> String? {
        let prefix = report.created_by_manager == true ? "Pro" : "Od"
        if let fullName = report.user_name?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            return "\(prefix) \(fullName)"
        }
        if let username = report.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return "\(prefix) @\(username)"
        }
        return nil
    }

    static func authorName(for report: UserReport) -> String {
        if let fullName = report.user_name?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            return fullName
        }
        if let username = report.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return "@\(username)"
        }
        return "Neznámý autor"
    }

    static func initials(for report: UserReport) -> String {
        let name = authorName(for: report)
        let parts = name.replacingOccurrences(of: "@", with: "").split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        if !letters.isEmpty {
            return letters.uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Profilová fotka (stejná logika jako docházka / lokality)

private enum ReportProfileImageURL {
    static func from(filename: String?) -> URL? {
        guard let name = filename?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
    }

    static func forReport(_ report: UserReport, fallbackFilename: String?) -> URL? {
        if let url = report.reportProfileImageURL {
            return url
        }
        return from(filename: fallbackFilename)
    }
}

private struct ReportAuthorAvatarView: View {
    let url: URL?
    var token: String?
    let size: CGFloat
    let tint: Color
    let initials: String

    var body: some View {
        Group {
            if let url {
                AuthenticatedProfileImageView(url: url, token: token, size: size)
            } else {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(initials)
                            .font(size >= 46 ? .subheadline.weight(.bold) : .caption.weight(.bold))
                            .foregroundStyle(tint)
                    }
            }
        }
        .overlay {
            Circle()
                .stroke(tint.opacity(0.35), lineWidth: 2)
        }
    }
}

// MARK: - Hlavní detail

struct ManagerProblemDetailView: View {
    let report: UserReport
    @Binding var selectedReport: UserReport?
    @EnvironmentObject private var authState: AuthState
    @State private var showReplySheet = false
    @State private var refreshedReport: UserReport?
    @State private var teamMemberProfileImage: String?

    private let managerReportsService = ManagerReportsService()
    private let teamMembersService = ManagerTeamMembersService()

    private var currentReport: UserReport {
        refreshedReport ?? report
    }

    private var authorProfileImageURL: URL? {
        ReportProfileImageURL.forReport(currentReport, fallbackFilename: teamMemberProfileImage)
    }

    private var tint: Color {
        ManagerReportAppearance.headerTint(for: currentReport)
    }

    private var reportStatus: ManagerReportAppearance.Status {
        ManagerReportAppearance.status(for: currentReport)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ReportDetailHeader(
                        report: currentReport,
                        tint: tint,
                        status: reportStatus,
                        topInset: proxy.safeAreaInsets.top
                    )

                    ReportDetailBody(
                        report: currentReport,
                        authToken: authState.authToken,
                        profileImageURL: authorProfileImageURL,
                        tint: tint,
                        status: reportStatus,
                        formatDate: formatDetailDate
                    )
                    .padding(.top, -28)
                    .padding(.bottom, 88)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottomTrailing) {
                replyFloatingButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await refreshReport() }
        .task(id: currentReport.id) {
            await loadAuthorProfileImageIfNeeded()
        }
        .sheet(isPresented: $showReplySheet) {
            ManagerReplyToReportView(report: currentReport) {
                showReplySheet = false
                Task { await refreshReport() }
            }
            .environmentObject(authState)
        }
        .onDisappear { selectedReport = nil }
    }

    private var replyFloatingButton: some View {
        Button {
            showReplySheet = true
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(tint.gradient)
                        .shadow(color: tint.opacity(0.45), radius: 14, y: 6)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Odpovědět")
    }

    private func formatDetailDate(_ dateString: String) -> String {
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
            await loadAuthorProfileImageIfNeeded()
        } catch {}
    }

    private func loadAuthorProfileImageIfNeeded() async {
        if currentReport.reportProfileImageURL != nil {
            teamMemberProfileImage = nil
            return
        }

        guard let token = authState.authToken, !token.isEmpty else { return }

        do {
            let members = try await teamMembersService.fetchMembers(token: token)
            if let userId = currentReport.user_id,
               let member = members.first(where: { $0.id == userId }) {
                teamMemberProfileImage = member.profile_image
                return
            }

            if let username = currentReport.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                let normalized = username.lowercased()
                teamMemberProfileImage = members.first {
                    ($0.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
                }?.profile_image
            }
        } catch {}
    }
}

// MARK: - Header

private struct ReportDetailHeader: View {
    let report: UserReport
    let tint: Color
    let status: ManagerReportAppearance.Status
    var topInset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    tint,
                    tint.opacity(0.82),
                    tint.opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 220, y: -40)
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 120, height: 120)
                .offset(x: -30, y: 60)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    headerTypeIcon

                    VStack(alignment: .leading, spacing: 3) {
                        if let badge = report.managerIssueTypeBadge {
                            Text(badge.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.6)
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Text("REPORT #\(report.id)")
                                .font(.caption2.weight(.bold))
                                .tracking(0.6)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        Text(report.managerListTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }

                ReportDetailStatusTrack(current: status)
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset + 52)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(report.managerListTitle), stav \(status.label)")
    }

    private var headerTypeIcon: some View {
        Image(systemName: ManagerReportAppearance.rowIcon(for: report))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.18), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}

private struct ReportDetailStatusTrack: View {
    let current: ManagerReportAppearance.Status

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ManagerReportAppearance.Status.allCases.enumerated()), id: \.offset) { index, step in
                let isActive = step.rawValue <= current.rawValue
                let isCurrent = step == current

                HStack(spacing: 0) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(isActive ? Color.white : Color.white.opacity(0.25))
                                .frame(width: isCurrent ? 30 : 24, height: isCurrent ? 30 : 24)
                            Image(systemName: step.icon)
                                .font(isCurrent ? .caption.weight(.bold) : .caption2.weight(.semibold))
                                .foregroundStyle(isActive ? tintForStep(step) : .white.opacity(0.5))
                        }

                        Text(step.label)
                            .font(.caption2.weight(isCurrent ? .bold : .medium))
                            .foregroundStyle(isCurrent ? .white : .white.opacity(isActive ? 0.85 : 0.55))
                    }
                    .frame(maxWidth: .infinity)

                    if index < ManagerReportAppearance.Status.allCases.count - 1 {
                        Capsule()
                            .fill(isActive && step.rawValue < current.rawValue ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                            .frame(height: 3)
                            .frame(maxWidth: 36)
                            .padding(.bottom, 18)
                    }
                }
            }
        }
    }

    private func tintForStep(_ step: ManagerReportAppearance.Status) -> Color {
        switch step {
        case .created: return .orange
        case .open: return .orange
        case .completed: return .green
        }
    }
}

// MARK: - Tělo

private struct ReportDetailBody: View {
    let report: UserReport
    var authToken: String?
    let profileImageURL: URL?
    let tint: Color
    let status: ManagerReportAppearance.Status
    let formatDate: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            authorRow
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 20)

            if let note = report.note, !note.isEmpty {
                problemSection(note)
            }

            factsSection

            if let statements = report.statements, !statements.isEmpty {
                timelineSection(statements)
            }

            if let images = report.images, !images.isEmpty {
                photosSection(images)
            }

            if let result = report.result, !result.isEmpty {
                resultSection(result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 20, y: -6)
        }
    }

    private var authorRow: some View {
        HStack(spacing: 14) {
            ReportAuthorAvatarView(
                url: profileImageURL,
                token: authToken,
                size: 48,
                tint: tint,
                initials: ManagerReportAppearance.initials(for: report)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(ManagerReportAppearance.authorName(for: report))
                    .font(.headline)

                if let direction = ManagerReportAppearance.directionLabel(for: report) {
                    Text(direction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let created = report.created_at, !created.isEmpty {
                    Text(formatDate(created))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func problemSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Popis", icon: "quote.opening")

            Text(note)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Informace", icon: "list.bullet.rectangle")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                if report.is_deferred_sale_issue {
                    factRow("Typ", report.issue_type_label ?? "Odložený prodej", icon: "tag.fill", tint: tint)
                } else if let label = report.issue_type_label, !label.isEmpty {
                    factRow("Typ", label, icon: "tag.fill", tint: tint)
                }

                if !report.is_deferred_sale_issue {
                    factRow("Obj. číslo", report.order_number ?? "—", icon: "number", tint: .primary)
                }

                factRow("Stav", report.statusDisplayCzech, icon: "circle.dotted", tint: statusTint)
                factRow("Dokončeno", report.isCompleted ? "Ano" : "Ne", icon: report.isCompleted ? "checkmark.circle.fill" : "hourglass", tint: report.isCompleted ? .green : .orange)

                if let updated = report.updated_at, !updated.isEmpty {
                    factRow("Naposledy upraveno", formatDate(updated), icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: .secondary)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 28)
    }

    private var statusTint: Color {
        switch status {
        case .created: return .orange
        case .open: return .orange
        case .completed: return .green
        }
    }

    private func timelineSection(_ statements: [ReportStatement]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Historie", icon: "bubble.left.and.bubble.right.fill")
                Spacer()
                Text("\(statements.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(Array(statements.enumerated()), id: \.offset) { index, item in
                    ReportDetailTimelineRow(
                        item: item,
                        formatDate: formatDate,
                        tint: tint,
                        isFirst: index == 0,
                        isLast: index == statements.count - 1
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
    }

    private func photosSection(_ images: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Přílohy", icon: "photo.on.rectangle.angled")
                .padding(.horizontal, 20)

            ReportDetailPhotoStrip(imagePaths: images, authToken: authToken)
        }
        .padding(.bottom, 28)
    }

    private func resultSection(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Výsledek", icon: "checkmark.seal.fill")
                .foregroundStyle(.green)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .padding(.top, 2)

                Text(result)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .labelStyle(SectionLabelStyle())
    }

    private func factRow(_ label: String, _ value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 11)
    }
}

private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.caption.weight(.semibold))
            configuration.title
                .font(.caption.weight(.bold))
                .tracking(0.4)
        }
    }
}

// MARK: - Timeline

private struct ReportDetailTimelineRow: View {
    let item: ReportStatement
    let formatDate: (String) -> String
    let tint: Color
    let isFirst: Bool
    let isLast: Bool

    private var isResult: Bool { item.is_result == true }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isFirst ? .clear : Color(uiColor: .separator).opacity(0.35))
                    .frame(width: 2, height: 10)

                Circle()
                    .fill(isResult ? Color.green : tint.opacity(0.85))
                    .frame(width: 9, height: 9)

                if !isLast {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(uiColor: .separator).opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 9)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if isResult {
                    Text("Výsledek")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let date = item.created_at, !date.isEmpty {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .padding(.bottom, isLast ? 0 : 2)
        }
    }
}

// MARK: - Fotky

private let managerReportImagesBaseURL = "https://provikart.cz/"

private struct ReportDetailPhotoStrip: View {
    let imagePaths: [String]
    var authToken: String?
    @State private var fullScreenURL: ManagerIdentifiableURL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(imagePaths.enumerated()), id: \.offset) { index, path in
                    if let url = resolvedImageURL(for: path) {
                        ReportDetailPhotoTile(url: url, token: authToken, index: index + 1, total: imagePaths.count) {
                            fullScreenURL = ManagerIdentifiableURL(url: url)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
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

private struct ReportDetailPhotoTile: View {
    let url: URL
    var token: String?
    let index: Int
    let total: Int
    var onTap: () -> Void

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if loadFailed {
                    Color(uiColor: .tertiarySystemFill)
                        .overlay {
                            Button("Znovu") { Task { await load() } }
                                .font(.caption.weight(.semibold))
                        }
                } else {
                    Color(uiColor: .tertiarySystemFill)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: 220, height: 160)
            .clipped()

            if total > 1 {
                Text("\(index)/\(total)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onTap() }
        .task(id: "\(url.absoluteString)|\(token ?? "")") { await load() }
    }

    private func load() async {
        await MainActor.run {
            loadFailed = false
            image = nil
        }
        let img = await ReportAttachmentImageLoader.loadUIImage(from: url, token: token)
        await MainActor.run {
            image = img
            loadFailed = (img == nil)
        }
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
                                        scale = min(max(lastScale * value, minScale), maxScale)
                                    }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scale = 1; lastScale = 1
                                    offset = .zero; lastOffset = .zero
                                }
                            }
                    } else if loadFailed {
                        ContentUnavailableView {
                            Label("Obrázek nelze načíst", systemImage: "photo")
                        } actions: {
                            Button("Zkusit znovu") { Task { await loadImage() } }
                                .tint(.white)
                        }
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .task(id: "\(url.absoluteString)|\(authToken ?? "")") { await loadImage() }
            .sheet(isPresented: $showShareSheet) {
                ManagerShareSheetView(items: loadedImage != nil ? [loadedImage!] : [url])
            }
        }
    }

    private func loadImage() async {
        await MainActor.run { loadFailed = false; loadedImage = nil }
        let img = await ReportAttachmentImageLoader.loadUIImage(from: url, token: authToken)
        await MainActor.run { loadedImage = img; loadFailed = (img == nil) }
    }
}

private struct ManagerShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Odpověď

private struct ManagerReplyToReportView: View {
    let report: UserReport
    var onSaved: () -> Void
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var statement = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let updateService = ReportUpdateService()
    private var tint: Color { ManagerReportAppearance.headerTint(for: report) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Report #\(report.id)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(report.managerListTitle)
                        .font(.headline)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(tint.opacity(0.08))

                TextEditor(text: $statement)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if statement.isEmpty {
                            Text("Napište odpověď…")
                                .foregroundStyle(.tertiary)
                                .padding(22)
                                .allowsHitTesting(false)
                        }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Odpověď")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Odeslat") { submitReply() }
                        .fontWeight(.semibold)
                        .disabled(statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("Odesláno", isPresented: $showSuccess) {
                Button("OK") { onSaved(); dismiss() }
            } message: {
                Text("Odpověď byla uložena do historie reportu.")
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
                try await updateService.updateManagerReport(
                    payload: ReportUpdatePayload(id: report.id, statement: trimmed),
                    token: authState.authToken
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
