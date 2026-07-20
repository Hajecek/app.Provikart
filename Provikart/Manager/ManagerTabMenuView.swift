//
//  ManagerTabMenuView.swift
//  Provikart
//
//  Role-specific tab menu pro manažera.
//

import SwiftUI
import UserNotifications

enum ManagerTabs: Hashable {
    case problems
    case attendance
    case performance
    case team
}

@MainActor
final class ManagerPerformanceBadgeState: ObservableObject {
    @Published var todayServicesCount: Int = 0

    private let service = ManagerTeamPerformanceService()
    private var didLoad = false

    func refreshIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await refresh(token: token)
    }

    func refresh(token: String?) async {
        guard let token, !token.isEmpty else { return }
        let month = Self.monthFormatter.string(from: Date())
        do {
            let payload = try await service.fetchPerformance(token: token, month: month)
            todayServicesCount = payload.todayServicesCount
            didLoad = true
        } catch {
            // Badge necháme beze změny – detailní chyba se řeší na stránce Výkon.
        }
    }

    func update(todayServicesCount: Int) {
        self.todayServicesCount = todayServicesCount
        didLoad = true
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()
}

@MainActor
final class ManagerNotificationsBadgeState: ObservableObject {
    @Published var unreadCount: Int = 0

    private let service = ManagerNotificationsService()
    private var didLoad = false
    private var pollingTask: Task<Void, Never>?
    private var tokenProvider: (() -> String?)?
    private var remoteObservers: [NSObjectProtocol] = []

    func refreshIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await refresh(token: token)
    }

    func refresh(token: String?) async {
        guard let token, !token.isEmpty else { return }
        do {
            // unread_count z API je celkový; limit 1 stačí pro badge.
            let payload = try await service.fetchNotifications(token: token, limit: 1)
            unreadCount = payload.unreadCount
            didLoad = true
            await syncAppIconBadge()
        } catch {
            // Badge necháme beze změny – detailní chyba se řeší v inboxu.
        }
    }

    func update(unreadCount: Int) {
        self.unreadCount = max(0, unreadCount)
        didLoad = true
        Task { await syncAppIconBadge() }
    }

    func startPolling(tokenProvider: @escaping () -> String?) {
        self.tokenProvider = tokenProvider
        startObservingRemoteNotifications()
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await refresh(token: tokenProvider())
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await refresh(token: tokenProvider())
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        stopObservingRemoteNotifications()
    }

    /// Po příchozí push notifikaci sjednotí zvonek s badge na ploše.
    private func startObservingRemoteNotifications() {
        stopObservingRemoteNotifications()
        let pushObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("didReceiveRemoteNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refresh(token: self.tokenProvider?())
            }
        }
        let unreadObserver = NotificationCenter.default.addObserver(
            forName: .managerNotificationsUnreadDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let count = notification.userInfo?["unread_count"] as? Int else { return }
            Task { @MainActor in
                self?.unreadCount = max(0, count)
                self?.didLoad = true
            }
        }
        remoteObservers = [pushObserver, unreadObserver]
    }

    private func stopObservingRemoteNotifications() {
        for observer in remoteObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        remoteObservers = []
    }

    /// Číslo na ikoně aplikace na ploše (stejné jako u zvonku).
    private func syncAppIconBadge() async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(max(0, unreadCount))
        } catch {
            // Bez oprávnění badge / systémová chyba – zvonek v appce dál funguje.
        }
    }

    func clearAppIconBadge() {
        unreadCount = 0
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }
}

struct ManagerTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @StateObject private var reportIssueSheet = ManagerReportIssueSheetState()
    @StateObject private var notificationsSheet = ManagerNotificationsSheetState()
    @StateObject private var performanceBadge = ManagerPerformanceBadgeState()
    @StateObject private var notificationsBadge = ManagerNotificationsBadgeState()
    @State private var selectedTab: ManagerTabs = .problems
    @State private var problemsRefreshToken = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Problémy", systemImage: "exclamationmark.bubble", value: .problems) {
                ManagerProblemsView(refreshToken: problemsRefreshToken)
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
                    .environmentObject(notificationsSheet)
                    .environmentObject(notificationsBadge)
            }

            Tab("Docházka", systemImage: "person.badge.clock", value: .attendance) {
                ManagerAttendanceView()
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
                    .environmentObject(notificationsSheet)
                    .environmentObject(notificationsBadge)
            }

            Tab("Výkon", systemImage: "chart.bar", value: .performance) {
                ManagerTeamPerformanceView()
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
                    .environmentObject(performanceBadge)
                    .environmentObject(notificationsSheet)
                    .environmentObject(notificationsBadge)
            }
            .badge(performanceBadge.todayServicesCount > 0 ? performanceBadge.todayServicesCount : 0)

            Tab("Tým", systemImage: "person.3", value: .team) {
                ManagerTeamProfilesView()
                    .environmentObject(authState)
                    .environmentObject(reportIssueSheet)
                    .environmentObject(notificationsSheet)
                    .environmentObject(notificationsBadge)
            }

        }
        .sheet(isPresented: $reportIssueSheet.isPresented) {
            ManagerReportIssueView(
                isPresented: $reportIssueSheet.isPresented,
                authState: authState,
                isModalPresentation: true,
                onClose: {
                    reportIssueSheet.isPresented = false
                    problemsRefreshToken = UUID()
                }
            )
            .environmentObject(authState)
        }
        .sheet(isPresented: $notificationsSheet.isPresented) {
            ManagerNotificationsView()
                .environmentObject(authState)
                .environmentObject(notificationsBadge)
        }
        .onChange(of: notificationsSheet.isPresented) { _, isPresented in
            if !isPresented {
                Task {
                    await notificationsBadge.refresh(token: authState.authToken)
                }
            }
        }
        .modifier(LoginApprovalBottomAccessoryModifier(approvalState: appLoginApprovalState))
        .task {
            await performanceBadge.refreshIfNeeded(token: authState.authToken)
            notificationsBadge.startPolling { [authState] in authState.authToken }
        }
        .onChange(of: authState.isLoggedIn) { _, isLoggedIn in
            if !isLoggedIn {
                notificationsBadge.clearAppIconBadge()
            }
        }
        .onDisappear {
            notificationsBadge.stopPolling()
        }
    }
}