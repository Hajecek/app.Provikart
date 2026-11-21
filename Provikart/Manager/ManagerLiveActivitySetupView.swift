//
//  ManagerLiveActivitySetupView.swift
//  Provikart
//
//  Výběr varianty a ruční start Live Activity pro manažera.
//  Obsah je ve sdíleném LiveActivityStudioView (stejný výběr mají všechny role).
//

import SwiftUI

struct ManagerLiveActivitySetupView: View {
    var showsCloseButton = false

    var body: some View {
        LiveActivityStudioView(role: .manager, showsCloseButton: showsCloseButton)
    }
}
