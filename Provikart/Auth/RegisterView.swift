//
//  RegisterView.swift
//  Provikart
//
//  Registrační obrazovka (zatím bez API napojení).
//

import SwiftUI
import PhotosUI

struct RegisterView: View {
    @EnvironmentObject private var authState: AuthState
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
    private var canSubmit: Bool {
        selectedTeamId != nil &&
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isPersonalNumberValid &&
        isEmailPrefixValid &&
        isUsernameValid &&
        password.count >= 8 &&
        !confirmPassword.isEmpty &&
        password == confirmPassword &&
        !isSubmitting
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

    var body: some View {
        ZStack {
            Image("background-login")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("Registrace")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)

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
                            .onChange(of: personalNumber) { _, newValue in
                                personalNumber = newValue.filter(\.isNumber)
                            }
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

                        TextField("Uživatelské jméno", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                        SecureField("Heslo (min. 8 znaků)", text: $password)
                            .textContentType(.newPassword)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                        SecureField("Potvrzení hesla", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

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
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if teams.isEmpty && !isLoadingTeams {
                        Text("Seznam týmů se nepodařilo načíst. Zkus to prosím znovu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        validateBeforeSubmit()
                        guard canSubmit else { return }
                        performRegister()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text("Registrovat se")
                                .fontWeight(.semibold)
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 8)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.7)

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
        .alert("Registrace dokončena", isPresented: $showInfoAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Účet byl vytvořen a uživatel je přihlášen.")
        }
    }

    private func validateBeforeSubmit() {
        if selectedTeamId == nil {
            errorMessage = "Vyberte tým."
        } else if !isPersonalNumberValid {
            errorMessage = "Osobní číslo musí mít 4-20 číslic."
        } else if !isEmailPrefixValid {
            errorMessage = "Email prefix je neplatný."
        } else if !isUsernameValid {
            errorMessage = "Uživatelské jméno musí mít 5-20 znaků (písmena, čísla, podtržítko)."
        } else if password.count < 8 {
            errorMessage = "Heslo musí mít alespoň 8 znaků."
        } else if password != confirmPassword {
            errorMessage = "Hesla se neshodují."
        } else {
            errorMessage = nil
        }
    }

    private func performRegister() {
        let payload = RegisterRequest(
            firstname: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastname: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            email: "\(emailPrefix.trimmingCharacters(in: .whitespacesAndNewlines))@o2.cz",
            password: password,
            personal_number: personalNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : personalNumber.trimmingCharacters(in: .whitespacesAndNewlines)
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

#Preview {
    NavigationStack {
        RegisterView()
    }
    .environmentObject(AuthState())
}
