//
//  AddView.swift
//  Provikart
//

import SwiftUI

struct AddView: View {
    @Binding var selectedTab: Tabs

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack {}
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
