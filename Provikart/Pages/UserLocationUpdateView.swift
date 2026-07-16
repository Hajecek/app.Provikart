//
//  UserLocationUpdateView.swift
//  Provikart
//
//  Nahlášení / úprava vlastní lokality na vybraný den.
//

import SwiftUI

@MainActor
final class UserLocationViewModel: ObservableObject {
    @Published var workDate: Date = Date()
    @Published var arrivalTime: Date = Date()
    @Published var locationName = ""
    @Published var note = ""
    @Published var existingLocation: UserLocationRecord?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let service = UserLocationUpdateService()
    private var loadGeneration = 0

    var isCurrentDay: Bool {
        Calendar.current.isDateInToday(workDate)
    }

    var hasExistingLocation: Bool {
        existingLocation?.hasContent == true
    }

    var dayTitle: String {
        Self.dayTitleFormatter.string(from: workDate)
    }

    var shortDayTitle: String {
        Self.shortDayFormatter.string(from: workDate)
    }

    var saveButtonTitle: String {
        hasExistingLocation ? "Uložit úpravy" : "Uložit lokalitu"
    }

    var canSave: Bool {
        !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
            && !isLoading
    }

    func moveDay(by offset: Int) {
        guard let updated = Calendar.current.date(byAdding: .day, value: offset, to: workDate) else { return }
        workDate = updated
    }

    func jumpToToday() {
        workDate = Date()
    }

    func loadLocation(token: String?) async {
        guard let token, !token.isEmpty else {
            existingLocation = nil
            errorMessage = "Nejste přihlášeni."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        let dateString = Self.apiDateFormatter.string(from: workDate)

        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            let result = try await service.fetchLocation(token: token, workDate: dateString)
            guard generation == loadGeneration else { return }
            applyFetchedLocation(result.location)
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            if Self.isCancellation(error) { return }
            if let locationError = error as? UserLocationUpdateError,
               case .notAuthenticated = locationError {
                errorMessage = locationError.localizedDescription
                return
            }
            if !hasExistingLocation && locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existingLocation = nil
                arrivalTime = roundedToHalfHour(Date())
                note = ""
            }
        }
    }

    func saveLocation(token: String?) async -> Bool {
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            errorMessage = "Zadejte název lokality."
            return false
        }
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return false
        }

        isSaving = true
        errorMessage = nil
        infoMessage = nil
        let wasExisting = hasExistingLocation

        let dateString = Self.apiDateFormatter.string(from: workDate)
        let timeString = Self.apiTimeFormatter.string(from: arrivalTime)
        let noteToSend = note.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let saved = try await service.updateLocation(
                token: token,
                workDate: dateString,
                locationName: trimmedLocation,
                arrivalTime: timeString,
                note: noteToSend.isEmpty ? nil : noteToSend
            )
            if let saved, saved.hasContent {
                applyFetchedLocation(saved)
            } else {
                existingLocation = UserLocationRecord(
                    fromLocal: trimmedLocation,
                    workDate: dateString,
                    arrivalTime: timeString,
                    note: noteToSend.isEmpty ? nil : noteToSend
                )
                locationName = trimmedLocation
                note = noteToSend
            }
            isSaving = false
            infoMessage = wasExisting
                ? "Lokalita pro tento den byla aktualizována."
                : "Lokalita byla úspěšně uložena."
            return true
        } catch {
            isSaving = false
            if Self.isCancellation(error) { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyFetchedLocation(_ location: UserLocationRecord?) {
        existingLocation = location
        if let location, location.hasContent {
            locationName = location.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            note = location.note ?? ""
            if let time = location.arrivalTimeDisplay,
               let parsed = Self.apiTimeFormatter.date(from: time) {
                arrivalTime = parsed
            } else {
                arrivalTime = roundedToHalfHour(Date())
            }
        } else {
            locationName = ""
            note = ""
            arrivalTime = roundedToHalfHour(Date())
        }
    }

    private func roundedToHalfHour(_ date: Date) -> Date {
        let minute = Calendar.current.component(.minute, from: date)
        let delta = minute < 30 ? (30 - minute) : (60 - minute)
        return Calendar.current.date(byAdding: .minute, value: delta, to: date) ?? date
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let apiTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "EEEE d. M. yyyy"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "d. M."
        return f
    }()
}

private extension UserLocationRecord {
    init(fromLocal locationName: String, workDate: String, arrivalTime: String, note: String?) {
        self.init(
            userId: nil,
            workDate: workDate,
            locationName: locationName,
            arrivalTime: arrivalTime,
            note: note,
            updatedAt: nil,
            updatedBy: nil
        )
    }
}

struct UserLocationUpdateView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @StateObject private var viewModel = UserLocationViewModel()
    @State private var showSuccessAlert = false
    @State private var appeared = false

    private enum Field {
        case location
        case note
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundAtmosphere

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        daySelector
                        headerBlock
                        editorBlock

                        if let errorMessage = viewModel.errorMessage {
                            feedbackBanner(text: errorMessage, tint: .red, icon: "exclamationmark.triangle.fill")
                        } else if let infoMessage = viewModel.infoMessage {
                            feedbackBanner(text: infoMessage, tint: .green, icon: "checkmark.circle.fill")
                        }

                        saveButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .overlay(alignment: .top) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.snappy(duration: 0.25), value: viewModel.isLoading)
            .animation(.snappy(duration: 0.28), value: viewModel.hasExistingLocation)
            .navigationTitle("Moje lokalita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
            .task {
                await viewModel.loadLocation(token: authState.authToken)
                withAnimation(.easeOut(duration: 0.45)) {
                    appeared = true
                }
            }
            .onChange(of: viewModel.workDate) { _, _ in
                focusedField = nil
                Task {
                    await viewModel.loadLocation(token: authState.authToken)
                }
            }
            .refreshable {
                await viewModel.loadLocation(token: authState.authToken)
            }
            .alert(
                viewModel.hasExistingLocation ? "Lokalita byla upravena" : "Lokalita byla uložena",
                isPresented: $showSuccessAlert
            ) {
                Button("Zůstat tady", role: .cancel) {}
                Button("Zpět") {
                    dismiss()
                }
            } message: {
                Text(
                    viewModel.hasExistingLocation
                        ? "Změny pro \(viewModel.dayTitle.lowercased()) jsou uložené."
                        : "Lokalita pro \(viewModel.dayTitle.lowercased()) je uložená."
                )
            }
        }
    }

    private var backgroundAtmosphere: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.16),
                    Color.accentColor.opacity(0.04),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: 140, y: -180)

            Circle()
                .fill(Color.cyan.opacity(0.06))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var daySelector: some View {
        HStack(spacing: 10) {
            dayStepButton(systemName: "chevron.left") {
                withAnimation(.snappy(duration: 0.22)) {
                    viewModel.moveDay(by: -1)
                }
            }

            VStack(spacing: 3) {
                Text(capitalized(viewModel.dayTitle))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())

                Text(viewModel.isCurrentDay ? "Dnes" : viewModel.shortDayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            dayStepButton(systemName: "chevron.right") {
                withAnimation(.snappy(duration: 0.22)) {
                    viewModel.moveDay(by: 1)
                }
            }

            if !viewModel.isCurrentDay {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        viewModel.jumpToToday()
                    }
                } label: {
                    Text("Dnes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.hasExistingLocation ? "mappin.circle.fill" : "mappin.and.ellipse")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(viewModel.hasExistingLocation ? Color.green : Color.accentColor)
                    .symbolEffect(.bounce, value: viewModel.hasExistingLocation)

                Text(viewModel.hasExistingLocation ? "Úprava lokality" : "Kam dnes jedete?")
                    .font(.title2.weight(.bold))
                    .contentTransition(.opacity)
            }

            Text(
                viewModel.hasExistingLocation
                    ? "Pro tento den už máte lokalitu uloženou. Upravte údaje a uložte změny."
                    : "Napište místo, čas příjezdu a případně krátkou poznámku."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if viewModel.hasExistingLocation {
                existingBadge
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var existingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("Lokalita pro tento den je už zadaná")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.1), in: Capsule())
    }

    private var editorBlock: some View {
        VStack(spacing: 0) {
            locationField

            Divider()
                .padding(.leading, 54)

            timeRow

            Divider()
                .padding(.leading, 54)

            noteField
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var locationField: some View {
        HStack(alignment: .top, spacing: 14) {
            fieldIcon("building.2.fill", tint: .accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("Lokalita")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Např. Brno – centrum", text: $viewModel.locationName)
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .location)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .note
                    }
            }
        }
        .padding(18)
    }

    private var timeRow: some View {
        HStack(spacing: 14) {
            fieldIcon("clock.fill", tint: .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Příjezd")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(timeLabel)
                    .font(.body.weight(.semibold))
            }

            Spacer(minLength: 0)

            DatePicker(
                "Příjezd",
                selection: $viewModel.arrivalTime,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .scaleEffect(0.95)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var noteField: some View {
        HStack(alignment: .top, spacing: 14) {
            fieldIcon("text.bubble.fill", tint: .blue)

            VStack(alignment: .leading, spacing: 6) {
                Text("Poznámka")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Volitelné — např. schůzka s klientem", text: $viewModel.note, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .note)
            }
        }
        .padding(18)
    }

    private func fieldIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var saveButton: some View {
        Button {
            focusedField = nil
            Task {
                let success = await viewModel.saveLocation(token: authState.authToken)
                if success {
                    showSuccessAlert = true
                }
            }
        } label: {
            ZStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.hasExistingLocation ? "checkmark.circle.fill" : "paperplane.fill")
                        Text(viewModel.saveButtonTitle)
                            .fontWeight(.semibold)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        viewModel.canSave
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.secondary.opacity(0.28))
                    )
                    .shadow(
                        color: viewModel.canSave ? Color.accentColor.opacity(0.28) : .clear,
                        radius: 14,
                        x: 0,
                        y: 8
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
        .sensoryFeedback(.success, trigger: showSuccessAlert)
    }

    private func feedbackBanner(text: String, tint: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func dayStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var timeLabel: String {
        Self.displayTimeFormatter.string(from: viewModel.arrivalTime)
    }

    private func capitalized(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()
}

#Preview {
    UserLocationUpdateView()
        .environmentObject(AuthState())
}
