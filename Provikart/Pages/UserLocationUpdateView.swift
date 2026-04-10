//
//  UserLocationUpdateView.swift
//  Provikart
//

import SwiftUI

struct UserLocationUpdateView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var workDate: Date = Date()
    @State private var arrivalTime: Date = Date()
    @State private var locationName = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false

    private let service = UserLocationUpdateService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Kdy a kam jedeš") {
                    DatePicker("Datum", selection: $workDate, displayedComponents: .date)
                    DatePicker("Příjezd", selection: $arrivalTime, displayedComponents: .hourAndMinute)

                    TextField("Lokalita", text: $locationName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                }

                Section("Poznámka (volitelné)") {
                    TextField("Např. schůzka s klientem", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button {
                        saveLocation()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Uložit lokalitu")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving || locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Moje lokalita")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Rozumný default: nejbližší půlhodina.
                arrivalTime = roundedToHalfHour(Date())
            }
            .alert("Lokalita byla úspěšně uložena", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Po potvrzení se vrátíte zpět na domovskou stránku.")
            }
        }
    }

    private func saveLocation() {
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        let dateString = Self.apiDateFormatter.string(from: workDate)
        let timeString = Self.apiTimeFormatter.string(from: arrivalTime)
        let noteToSend = note.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                _ = try await service.updateLocation(
                    token: authState.authToken,
                    workDate: dateString,
                    locationName: trimmedLocation,
                    arrivalTime: timeString,
                    note: noteToSend.isEmpty ? nil : noteToSend
                )
                await MainActor.run {
                    isSaving = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func roundedToHalfHour(_ date: Date) -> Date {
        let minute = Calendar.current.component(.minute, from: date)
        let delta = minute < 30 ? (30 - minute) : (60 - minute)
        return Calendar.current.date(byAdding: .minute, value: delta, to: date) ?? date
    }

    private static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let apiTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()
}

#Preview {
    UserLocationUpdateView()
        .environmentObject(AuthState())
}
