//
//  ManagerProblemsView.swift
//  Provikart
//
//  Manager varianta stránky Problémy.
//

import SwiftUI

struct ManagerProblemsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ProblemsViewModel()

    private var reports: [UserReport] {
        viewModel.reports
    }

    private var incompleteCount: Int {
        viewModel.reports.filter { !$0.isCompleted }.count
    }

    private var completedCount: Int {
        viewModel.reports.filter(\.isCompleted).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.reports.isEmpty {
                    ProgressView("Načítám reporty…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.reports.isEmpty {
                    ContentUnavailableView(
                        "Nepodařilo se načíst reporty",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                } else if reports.isEmpty {
                    ContentUnavailableView(
                        "Žádné reporty",
                        systemImage: "checkmark.circle",
                        description: Text("Momentálně nejsou k dispozici žádné položky.")
                    )
                } else {
                    List {
                        Section {
                            statsRow
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                        }

                        Section("Seznam reportů") {
                            ForEach(reports) { report in
                                NavigationLink {
                                    ReportDetailView(
                                        report: report,
                                        openEditOnAppear: false,
                                        selectedReport: .constant(nil)
                                    )
                                } label: {
                                    managerReportRow(report)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
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

    private var statsRow: some View {
        HStack(spacing: 12) {
            managerStatCard(
                title: "Nedokončené",
                value: "\(incompleteCount)",
                color: .orange,
                systemImage: "clock.badge.exclamationmark"
            )
            managerStatCard(
                title: "Dokončené",
                value: "\(completedCount)",
                color: .green,
                systemImage: "checkmark.circle.fill"
            )
            managerStatCard(
                title: "Celkem",
                value: "\(viewModel.reports.count)",
                color: .blue,
                systemImage: "tray.full.fill"
            )
        }
        .padding(.horizontal, 16)
    }

    private func managerStatCard(title: String, value: String, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func managerReportRow(_ report: UserReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.order_number ?? "Objednávka bez čísla")
                    .font(.headline)
                Spacer()
                statusBadge(report)
            }

            let previewText = report.user_note ?? report.note ?? report.statement
            if let previewText, !previewText.isEmpty {
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let created = report.created_at, !created.isEmpty {
                    Label(created, systemImage: "calendar")
                }
                if report.created_by_manager == true {
                    Label("Vytvořil manažer", systemImage: "person.badge.shield.checkmark")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ report: UserReport) -> some View {
        let completed = report.isCompleted
        return Text(completed ? "Dokončeno" : "Čeká")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(completed ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundStyle(completed ? Color.green : Color.orange)
            .clipShape(Capsule())
    }
}
