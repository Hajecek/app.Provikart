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
