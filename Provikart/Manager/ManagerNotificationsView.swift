//
//  ManagerNotificationsView.swift
//  Provikart
//
//  Inbox oznámení manažera (zvonek).
//

import SwiftUI

@MainActor
final class ManagerNotificationsViewModel: ObservableObject {
    @Published var notifications: [ManagerNotificationItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isMarkingAll = false

    private let service = ManagerNotificationsService()
    private let reportsService = ManagerReportsService()

    func load(token: String?, badgeState: ManagerNotificationsBadgeState) async {
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload = try await service.fetchNotifications(token: token)
            notifications = payload.notifications
            badgeState.update(unreadCount: payload.unreadCount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRead(
        token: String?,
        item: ManagerNotificationItem,
        isRead: Bool,
        badgeState: ManagerNotificationsBadgeState
    ) async {
        guard let token, !token.isEmpty else { return }
        do {
            let unread = try await service.setRead(token: token, key: item.key, isRead: isRead)
            if let index = notifications.firstIndex(where: { $0.key == item.key }) {
                notifications[index] = notifications[index].withReadState(isRead)
            }
            badgeState.update(unreadCount: unread)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllRead(token: String?, badgeState: ManagerNotificationsBadgeState) async {
        guard let token, !token.isEmpty else { return }
        isMarkingAll = true
        defer { isMarkingAll = false }
        do {
            let unread = try await service.markAllRead(token: token)
            notifications = notifications.map { $0.withReadState(true) }
            badgeState.update(unreadCount: unread)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func findReport(token: String?, reportId: Int) async -> UserReport? {
        do {
            let result = try await reportsService.fetchManagerReports(
                token: token,
                filters: Set(ManagerReportsFilter.allCases)
            )
            return result.reports.first { $0.id == reportId }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct ManagerNotificationsView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var notificationsBadge: ManagerNotificationsBadgeState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = ManagerNotificationsViewModel()
    @State private var selectedReport: UserReport?
    @State private var isOpeningReport = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    ProgressView("Načítám oznámení…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.notifications.isEmpty {
                    ContentUnavailableView(
                        "Oznámení se nepodařilo načíst",
                        systemImage: "bell.slash",
                        description: Text(message)
                    )
                } else if viewModel.notifications.isEmpty {
                    ContentUnavailableView(
                        "Žádná oznámení",
                        systemImage: "bell",
                        description: Text("Až něco přibude, uvidíš to tady.")
                    )
                } else {
                    listContent
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Oznámení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.notifications.contains(where: { !$0.is_read }) {
                        Button {
                            Task {
                                await viewModel.markAllRead(
                                    token: authState.authToken,
                                    badgeState: notificationsBadge
                                )
                            }
                        } label: {
                            if viewModel.isMarkingAll {
                                ProgressView()
                            } else {
                                Text("Přečíst vše")
                            }
                        }
                        .disabled(viewModel.isMarkingAll)
                    }
                }
            }
            .navigationDestination(item: $selectedReport) { report in
                ManagerProblemDetailView(
                    report: report,
                    selectedReport: $selectedReport
                )
                .environmentObject(authState)
            }
            .overlay {
                if isOpeningReport {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        ProgressView("Otevírám…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .refreshable {
                await viewModel.load(token: authState.authToken, badgeState: notificationsBadge)
            }
            .task {
                await viewModel.load(token: authState.authToken, badgeState: notificationsBadge)
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.notifications) { item in
                Button {
                    Task { await open(item) }
                } label: {
                    ManagerNotificationRow(item: item, authToken: authState.authToken)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if item.is_read {
                        Button {
                            Task {
                                await viewModel.setRead(
                                    token: authState.authToken,
                                    item: item,
                                    isRead: false,
                                    badgeState: notificationsBadge
                                )
                            }
                        } label: {
                            Label("Nepřečtené", systemImage: "envelope.badge")
                        }
                        .tint(.orange)
                    } else {
                        Button {
                            Task {
                                await viewModel.setRead(
                                    token: authState.authToken,
                                    item: item,
                                    isRead: true,
                                    badgeState: notificationsBadge
                                )
                            }
                        } label: {
                            Label("Přečtené", systemImage: "envelope.open")
                        }
                        .tint(.blue)
                    }
                }
                .contextMenu {
                    if item.is_read {
                        Button {
                            Task {
                                await viewModel.setRead(
                                    token: authState.authToken,
                                    item: item,
                                    isRead: false,
                                    badgeState: notificationsBadge
                                )
                            }
                        } label: {
                            Label("Označit jako nepřečtené", systemImage: "envelope.badge")
                        }
                    } else {
                        Button {
                            Task {
                                await viewModel.setRead(
                                    token: authState.authToken,
                                    item: item,
                                    isRead: true,
                                    badgeState: notificationsBadge
                                )
                            }
                        } label: {
                            Label("Označit jako přečtené", systemImage: "envelope.open")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func open(_ item: ManagerNotificationItem) async {
        if !item.is_read {
            await viewModel.setRead(
                token: authState.authToken,
                item: item,
                isRead: true,
                badgeState: notificationsBadge
            )
        }

        guard let reportId = item.report_id else { return }
        isOpeningReport = true
        defer { isOpeningReport = false }
        if let report = await viewModel.findReport(token: authState.authToken, reportId: reportId) {
            selectedReport = report
        }
    }
}

private struct ManagerNotificationRow: View {
    let item: ManagerNotificationItem
    let authToken: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(item.is_read ? .subheadline : .subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    if let relative = relativeTime(item.created_at) {
                        Text(relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let body = item.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let type = item.type_label?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
                    Text(type)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }

            if !item.is_read {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = item.avatarURL {
            AuthenticatedProfileImageView(url: url, token: authToken, size: 40)
        } else {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                Image(systemName: item.systemImageName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
        }
    }

    private func relativeTime(_ raw: String?) -> String? {
        guard let raw, let date = Self.parseDate(raw) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
