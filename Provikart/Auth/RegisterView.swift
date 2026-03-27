//
//  RegisterView.swift
//  Provikart
//
//  Registrační obrazovka (zatím bez API napojení).
//

import SwiftUI
import PhotosUI
import UIKit

struct RegisterView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var currentStep: Int = 1
    @State private var selectedTeamId: Int?
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var personalNumber: String = ""
    @State private var emailPrefix: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var teams: [RegistrationTeamOption] = []
    @State private var isLoadingTeams = false
    @State private var showInfoAlert = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let authService = AuthService()
    private var canSubmitFinal: Bool {
        isStep1Valid &&
        isStep2Valid &&
        selectedPhotoData != nil &&
        !isSubmitting
    }

    private var isStep1Valid: Bool {
        selectedTeamId != nil &&
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isPersonalNumberValid &&
        isEmailPrefixValid
    }

    private var isStep2Valid: Bool {
        isUsernameValid &&
        password.count >= 8 &&
        password.range(of: "[A-Za-z]", options: .regularExpression) != nil &&
        password.range(of: "[0-9]", options: .regularExpression) != nil &&
        !confirmPassword.isEmpty &&
        password == confirmPassword
    }

    private var isPersonalNumberValid: Bool {
        personalNumber.count >= 4 && personalNumber.count <= 20
    }

    private var isEmailPrefixValid: Bool {
        let trimmed = emailPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil
    }

    private var isUsernameValid: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 && trimmed.count <= 20 else { return false }
        return trimmed.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil
    }

    private var progressValue: Double {
        Double(currentStep) / 3.0
    }

    private var selectedTeamName: String {
        teams.first(where: { $0.id == selectedTeamId })?.name ?? "Nevyplněno"
    }

    private var fullEmail: String {
        "\(emailPrefix.trimmingCharacters(in: .whitespacesAndNewlines))@o2.cz"
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("Registrace")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)

                    VStack(spacing: 10) {
                        HStack {
                            Text("Krok \(currentStep) ze 3")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 8)

                    if currentStep == 1 {
                        stepOneView
                    } else if currentStep == 2 {
                        stepTwoView
                    } else {
                        stepThreeView
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                            .padding(.horizontal, 8)
                    }

                    if teams.isEmpty && !isLoadingTeams && currentStep == 1 {
                        Text("Seznam týmů se nepodařilo načíst. Zkus to prosím znovu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                            .padding(.horizontal, 8)
                    }

                    stepActions

                    Text("Tým a profilová fotka jsou zatím pouze lokální v aplikaci a neodesílají se do API.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Registrace")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTeams()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                selectedPhotoData = try? await newItem?.loadTransferable(type: Data.self)
            }
        }
        .onChange(of: personalNumber) { _, newValue in
            personalNumber = newValue.filter(\.isNumber)
        }
        .alert("Registrace dokončena", isPresented: $showInfoAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Účet byl vytvořen a uživatel je přihlášen.")
        }
    }

    private var stepOneView: some View {
        VStack(spacing: 12) {
            Picker("Tým", selection: $selectedTeamId) {
                if isLoadingTeams {
                    Text("Načítám týmy...").tag(nil as Int?)
                } else {
                    Text("Vyberte tým").tag(nil as Int?)
                }
                ForEach(teams) { team in
                    Text(team.name).tag(Optional(team.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .disabled(isLoadingTeams || teams.isEmpty)

            HStack(spacing: 12) {
                TextField("Jméno", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                TextField("Příjmení", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }

            TextField("Osobní číslo (4-20 číslic)", text: $personalNumber)
                .keyboardType(.numberPad)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            HStack(spacing: 8) {
                TextField("Pracovní email", text: $emailPrefix)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                Text("@o2.cz")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var stepTwoView: some View {
        VStack(spacing: 12) {
            TextField("Uživatelské jméno", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            SecureField("Heslo (min. 8 znaků, písmeno + číslo)", text: $password)
                .textContentType(.newPassword)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            SecureField("Potvrzení hesla", text: $confirmPassword)
                .textContentType(.newPassword)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var stepThreeView: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: selectedPhotoData == nil ? "camera.fill" : "checkmark.circle.fill")
                        .foregroundStyle(selectedPhotoData == nil ? Color.accentColor : .green)
                    Text(selectedPhotoData == nil ? "Vybrat profilovou fotku" : "Profilová fotka vybrána")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Shrnutí údajů")
                    .font(.headline)
                summaryRow(label: "Tým", value: selectedTeamName)
                summaryRow(label: "Jméno", value: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces))
                summaryRow(label: "Osobní číslo", value: personalNumber)
                summaryRow(label: "Email", value: fullEmail)
                summaryRow(label: "Uživatelské jméno", value: username)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "Nevyplněno" : value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var stepActions: some View {
        HStack(spacing: 12) {
            if currentStep > 1 {
                Button("Zpět") {
                    errorMessage = nil
                    currentStep -= 1
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if currentStep < 3 {
                Button("Pokračovat") {
                    goToNextStep()
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            } else {
                Button {
                    validateFinalStep()
                    guard canSubmitFinal else { return }
                    performRegister()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text("Dokončit registraci")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(!canSubmitFinal)
                .opacity(canSubmitFinal ? 1 : 0.7)
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 8)
    }

    private func goToNextStep() {
        if currentStep == 1 {
            validateStepOne()
            guard isStep1Valid else { return }
        }
        if currentStep == 2 {
            validateStepTwo()
            guard isStep2Valid else { return }
        }
        errorMessage = nil
        currentStep += 1
    }

    private func validateStepOne() {
        if selectedTeamId == nil {
            errorMessage = "Vyberte tým."
        } else if !isPersonalNumberValid {
            errorMessage = "Osobní číslo musí mít 4-20 číslic."
        } else if !isEmailPrefixValid {
            errorMessage = "Email prefix je neplatný."
        } else {
            errorMessage = nil
        }
    }

    private func validateStepTwo() {
        if !isUsernameValid {
            errorMessage = "Uživatelské jméno musí mít 5-20 znaků (písmena, čísla, podtržítko)."
        } else if password.count < 8 {
            errorMessage = "Heslo musí mít alespoň 8 znaků."
        } else if password.range(of: "[A-Za-z]", options: .regularExpression) == nil {
            errorMessage = "Heslo musí obsahovat alespoň jedno písmeno."
        } else if password.range(of: "[0-9]", options: .regularExpression) == nil {
            errorMessage = "Heslo musí obsahovat alespoň jedno číslo."
        } else if password != confirmPassword {
            errorMessage = "Hesla se neshodují."
        } else {
            errorMessage = nil
        }
    }

    private func validateFinalStep() {
        if selectedPhotoData == nil {
            errorMessage = "Vyber profilovou fotku."
            return
        }
        validateStepTwo()
    }

    private func performRegister() {
        let imageBase64 = compressedProfileImageBase64(from: selectedPhotoData)
        let payload = RegisterRequest(
            firstname: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastname: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            email: fullEmail,
            password: password,
            personal_number: personalNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : personalNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            team_id: selectedTeamId,
            profile_image_base64: imageBase64
        )

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let response = try await authService.register(payload: payload)
                await MainActor.run {
                    isSubmitting = false
                    authState.setLoggedIn(true, user: response.user, token: response.token)
                    showInfoAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func compressedProfileImageBase64(from data: Data?) -> String? {
        guard
            let data,
            let image = UIImage(data: data)
        else { return nil }

        let resized = image.resizedForUpload(maxLongEdge: 900)
        var quality: CGFloat = 0.75
        var jpeg = resized.jpegData(compressionQuality: quality)
        let maxBytes = 450 * 1024
        while let jpg = jpeg, jpg.count > maxBytes, quality > 0.25 {
            quality -= 0.1
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        return jpeg?.base64EncodedString()
    }

    @MainActor
    private func loadTeams() async {
        guard teams.isEmpty else { return }
        isLoadingTeams = true
        defer { isLoadingTeams = false }

        do {
            teams = try await authService.fetchRegistrationTeams()
        } catch {
            teams = []
        }
    }
}

private extension UIImage {
    func resizedForUpload(maxLongEdge: CGFloat) -> UIImage {
        let original = size
        guard original.width > maxLongEdge || original.height > maxLongEdge else { return self }
        let ratio = min(maxLongEdge / original.width, maxLongEdge / original.height)
        let newSize = CGSize(width: original.width * ratio, height: original.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    }
    .environmentObject(AuthState())
}
