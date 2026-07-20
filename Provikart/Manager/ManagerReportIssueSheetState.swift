//
//  ManagerReportIssueSheetState.swift
//  Provikart
//
//  Sdílené otevření formuláře pro nahlášení problému z toolbaru.
//

import SwiftUI

@MainActor
final class ManagerReportIssueSheetState: ObservableObject {
    @Published var isPresented = false
}

@MainActor
final class ManagerNotificationsSheetState: ObservableObject {
    @Published var isPresented = false
}

struct ManagerAddReportToolbarButton: View {
    @EnvironmentObject private var reportIssueSheet: ManagerReportIssueSheetState

    var body: some View {
        Button {
            reportIssueSheet.isPresented = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Přidat report")
    }
}

struct ManagerNotificationsBellButton: View {
    @EnvironmentObject private var notificationsSheet: ManagerNotificationsSheetState
    @EnvironmentObject private var notificationsBadge: ManagerNotificationsBadgeState

    var body: some View {
        Button {
            notificationsSheet.isPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    // Místo pro badge uvnitř bounds toolbar itemu (navbar ořezává overflow).
                    .padding(.trailing, notificationsBadge.unreadCount > 0 ? 8 : 0)
                    .padding(.top, notificationsBadge.unreadCount > 0 ? 4 : 0)

                if notificationsBadge.unreadCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, notificationsBadge.unreadCount > 9 ? 4 : 0)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.red, in: Capsule())
                        .zIndex(1)
                }
            }
            .frame(minWidth: 36, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            notificationsBadge.unreadCount > 0
                ? "Oznámení, \(notificationsBadge.unreadCount) nepřečtených"
                : "Oznámení"
        )
    }

    private var badgeText: String {
        notificationsBadge.unreadCount > 99 ? "99+" : "\(notificationsBadge.unreadCount)"
    }
}
