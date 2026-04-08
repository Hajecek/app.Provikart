//
//  ManagerLocationsSheetView.swift
//  Provikart
//
//  Denní přehled lokalit členů týmu pro manažera.
//

import SwiftUI

@MainActor
final class ManagerLocationsViewModel: ObservableObject {
    @Published var selectedDate: Date = Date()
    @Published var items: [ManagerLocationItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = ManagerLocationsService()

    func load(token: String?) async {
        guard let token, !token.isEmpty else {
            items = []
            errorMessage = "Nejste přihlášeni."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let date = Self.apiDateFormatter.string(from: selectedDate)
            let payload = try await service.fetchLocations(token: token, workDate: date)
            items = payload
            isLoading = false
        } catch {
            items = []
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func displayName(for item: ManagerLocationItem) -> String {
        if !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return item.name
        }
        if let username = item.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(item.userId)"
    }

    private static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

}

struct ManagerLocationsSheetView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManagerLocationsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Načítám lokality…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "Nepodařilo se načíst lokality",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "Bez záznamu",
                        systemImage: "mappin.slash",
                        description: Text("Pro vybraný den nejsou zatím uložené žádné lokality.")
                    )
                } else {
                    List {
                        Section {
                            DatePicker("Den", selection: $viewModel.selectedDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }

                        Section("Členové týmu (\(viewModel.items.count))") {
                            ForEach(viewModel.items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(viewModel.displayName(for: item))
                                            .font(.headline)
                                        Spacer(minLength: 8)
                                        if let arrival = item.arrivalTime, !arrival.isEmpty {
                                            Label(arrival, systemImage: "clock")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(.blue)
                                        Text(item.locationName.isEmpty ? "Nezadáno" : item.locationName)
                                            .font(.subheadline)
                                    }
                                    if let note = item.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Lokality týmu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                Task {
                    await viewModel.load(token: authState.authToken)
                }
            }
            .refreshable {
                await viewModel.load(token: authState.authToken)
            }
            .task {
                await viewModel.load(token: authState.authToken)
            }
        }
    }
}

#Preview {
    ManagerLocationsSheetView()
        .environmentObject(AuthState())
}
