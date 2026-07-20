//
//  ManagerNotificationsView.swift
//  Provikart
//
//  Inbox oznámení manažera (zvonek) – rozdělený do kategorií.
//

import SwiftUI

@MainActor
final class ManagerNotificationsViewModel: ObservableObject {
    @Published var notifications: [ManagerNotificationItem] = []
    @Published var selectedCategory: ManagerNotificationCategory? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isMarkingAll = false

    private let service = ManagerNotificationsService()
    private let reportsService = ManagerReportsService()

    var availableCategories: [ManagerNotificationCategory] {
        let set = Set(notifications.map(\.category))
        return set.sorted()
    }

    var filteredNotifications: [ManagerNotificationItem] {
        guard let selectedCategory else { return notifications }
        return notifications.filter { $0.category == selectedCategory }
    }

    var sections: [(category: ManagerNotificationCategory, items: [ManagerNotificationItem])] {
        let grouped = Dictionary(grouping: filteredNotifications, by: \.category)
        return grouped.keys.sorted().compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    func count(for category: ManagerNotificationCategory) -> Int {
        notifications.filter { $0.category == category }.count
    }

    func unreadCount(for category: ManagerNotificationCategory) -> Int {
        notifications.filter { $0.category == category && !$0.is_read }.count
    }

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
            if let selectedCategory, !availableCategories.contains(selectedCategory) {
                self.selectedCategory = nil
            }
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
            if viewModel.availableCategories.count > 1 {
                Section {
                    categoryFilters
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if viewModel.filteredNotifications.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nic v této kategorii",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Zkus jiný filtr nebo stáhni oznámení znovu.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(viewModel.sections, id: \.category) { section in
                    Section {
                        ForEach(section.items) { item in
                            notificationRow(item)
                        }
                    } header: {
                        categorySectionHeader(
                            category: section.category,
                            count: section.items.count,
                            unread: section.items.filter { !$0.is_read }.count
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: "Vše",
                    icon: "bell.fill",
                    count: viewModel.notifications.count,
                    unread: viewModel.notifications.filter { !$0.is_read }.count,
                    selected: viewModel.selectedCategory == nil
                ) {
                    viewModel.selectedCategory = nil
                }

                ForEach(viewModel.availableCategories) { category in
                    filterChip(
                        title: category.title,
                        icon: category.systemImage,
                        count: viewModel.count(for: category),
                        unread: viewModel.unreadCount(for: category),
                        selected: viewModel.selectedCategory == category
                    ) {
                        viewModel.selectedCategory = category
                    }
                }
            }
        }
    }

    private func filterChip(
        title: String,
        icon: String,
        count: Int,
        unread: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(selected ? Color.primary.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                    )
                if unread > 0 {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                Capsule()
                    .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
    }

    private func categorySectionHeader(
        category: ManagerNotificationCategory,
        count: Int,
        unread: Int
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.systemImage)
            Text(category.title)
            Spacer(minLength: 0)
            if unread > 0 {
                Text("\(unread) nových")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func notificationRow(_ item: ManagerNotificationItem) -> some View {
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

                if let name = item.user_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    Text(name)
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
