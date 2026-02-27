//
//  AddView.swift
//  Provikart
//

import SwiftUI

struct AddView: View {
    @Binding var selectedTab: Tabs
    @EnvironmentObject private var authState: AuthState
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(greetingText)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        TextField("Zeptej se na cokoli", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                        Button {
                            // TODO: hlasové vyhledávání
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 38/255, green: 38/255, blue: 38/255))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedTab = .home
                    } label: {
                        Image(systemName: "house")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
        }
    }

    /// Pozdrav podle denní doby: Dobré ráno, Dobré dopoledne, Dobré odpoledne, Dobrý večer.
    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9: return "Dobré ráno"
        case 9..<12: return "Dobré dopoledne"
        case 12..<18: return "Dobré odpoledne"
        default: return "Dobrý večer"
        }
    }

    private var userName: String {
        if let first = authState.currentUser?.firstname, !first.isEmpty { return first }
        if let name = authState.currentUser?.name, !name.isEmpty { return name }
        let first = authState.currentUser?.firstname ?? ""
        let last = authState.currentUser?.lastname ?? ""
        let composed = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !composed.isEmpty { return composed }
        if let username = authState.currentUser?.username, !username.isEmpty { return username }
        return ""
    }

    private var greetingText: String {
        if userName.isEmpty {
            return "\(timeGreeting), co dnes vymyslíme?"
        }
        return "\(timeGreeting), \(userName), co dnes vymyslíme?"
    }
}

// MARK: - Sheet s výběrem typu přidání (používá TabMenuView)

struct AddTypeSheetView: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: Tabs
    @Binding var navigatingToAddFromSheet: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    // TODO: Normální přidání
                    isPresented = false
                    dismiss()
                } label: {
                    Label("Normální přidání", systemImage: "plus.circle.fill")
                }

                Button {
                    navigatingToAddFromSheet = true
                    isPresented = false
                    selectedTab = .add
                    dismiss()
                } label: {
                    Label("AI objednávka", systemImage: "sparkles")
                }
            }
            .navigationTitle("Přidat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AddView(selectedTab: .constant(.add))
        .environmentObject(AuthState())
}
