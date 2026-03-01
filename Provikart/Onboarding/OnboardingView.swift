//
//  OnboardingView.swift
//  Provikart
//
//  Onboarding v iOS 26 Liquid Glass stylu (pův. Balaji Venkatesh).
//

import LocalAuthentication
import SwiftUI
import UserNotifications

struct iOS26StyleOnBoarding: View {
    var tint: Color = .blue
    var hideBezels: Bool = false
    var items: [Item]
    /// Volitelná akce před přechodem na další krok: (index kroku, pokračovat).
    var stepAction: ((Int, @escaping () -> Void) -> Void)? = nil
    var onComplete: () -> ()
    /// View Properties
    @State private var currentIndex: Int = 0
    @State private var screenshotSize: CGSize = .zero
    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenshotView()
                .compositingGroup()
                .scaleEffect(
                    items[currentIndex].zoomScale,
                    anchor: items[currentIndex].zoomAnchor
                )
                .padding(.top, 35)
                .padding(.horizontal, 30)
                .padding(.bottom, 220)

            VStack(spacing: 10) {
                TextContentView()
                IndicatorView()
                ContinueButton()
            }
            .padding(.top, 20)
            .padding(.horizontal, 15)
            .frame(height: 210)
            .background {
                VariableGlassBlur(15)
            }

            BackButton()
        }
        .preferredColorScheme(.dark)
    }

    /// Screenshot View
    @ViewBuilder
    func ScreenshotView() -> some View {
        let shape = ConcentricRectangle(corners: .concentric, isUniform: true)

        GeometryReader {
            let size = $0.size

            Rectangle()
                .fill(.black)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]

                        Group {
                            if let screenshot = item.screenshot {
                                Image(uiImage: screenshot)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .onGeometryChange(for: CGSize.self) {
                                        $0.size
                                    } action: { newValue in
                                        guard index == 0 && screenshotSize == .zero else { return }
                                        screenshotSize = newValue
                                    }
                                    .clipShape(shape)
                            } else {
                                Rectangle()
                                    .fill(.black)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: .init(get: {
                return currentIndex
            }, set: { _ in }))
        }
        .clipShape(shape)
        .overlay {
            if screenshotSize != .zero && !hideBezels {
                /// Device Frame UI
                ZStack {
                    shape
                        .stroke(.white, lineWidth: 6)

                    shape
                        .stroke(.black, lineWidth: 4)

                    shape
                        .stroke(.black, lineWidth: 6)
                        .padding(4)
                }
                .padding(-7)
            }
        }
        .frame(
            maxWidth: screenshotSize.width == 0 ? nil : screenshotSize.width,
            maxHeight: screenshotSize.height == 0 ? nil : screenshotSize.height
        )
        .containerShape(RoundedRectangle(cornerRadius: deviceCornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Text Content View
    @ViewBuilder
    func TextContentView() -> some View {
        GeometryReader {
            let size = $0.size

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        let isActive = currentIndex == index

                        VStack(spacing: 6) {
                            Text(item.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundStyle(.white)

                            Text(item.subtitle)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: size.width)
                        .compositingGroup()
                        /// Only The current Item is visible others are blurred out!
                        .blur(radius: isActive ? 0 : 30)
                        .opacity(isActive ? 1 : 0)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .scrollTargetBehavior(.paging)
            .scrollClipDisabled()
            .scrollPosition(id: .init(get: {
                return currentIndex
            }, set: { _ in }))
        }
    }

    /// Indicator View
    @ViewBuilder
    func IndicatorView() -> some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let isActive: Bool = currentIndex == index

                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.4))
                    .frame(width: isActive ? 25 : 6, height: 6)
            }
        }
        .padding(.bottom, 5)
    }

    /// Bottom Continue Button
    @ViewBuilder
    func ContinueButton() -> some View {
        Button {
            let advance = {
                if currentIndex == items.count - 1 {
                    onComplete()
                }
                withAnimation(animation) {
                    currentIndex = min(currentIndex + 1, items.count - 1)
                }
            }
            if let action = stepAction {
                action(currentIndex, advance)
            } else {
                advance()
            }
        } label: {
            Text(currentIndex == items.count - 1 ? "Vrhnout se do aplikace" : "Pokračovat")
                .fontWeight(.medium)
                .contentTransition(.numericText())
                .padding(.vertical, 6)
        }
        .tint(tint)
        .buttonStyle(.glassProminent)
        .buttonSizing(.flexible)
        .padding(.horizontal, 30)
    }

    /// Back Button
    @ViewBuilder
    func BackButton() -> some View {
        Button {
            withAnimation(animation) {
                currentIndex = max(currentIndex - 1, 0)
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3)
                .frame(width: 20, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 15)
        .padding(.top, 5)
    }

    /// Variable Glass Effect Blur
    @ViewBuilder
    func VariableGlassBlur(_ radius: CGFloat) -> some View {
        /// ADJUST THESE PROPERTIES ACCORDING TO YOUR OWN NEEDS!
        let tint: Color = .black.opacity(0.5)
        Rectangle()
            .fill(tint)
            .glassEffect(.clear, in: .rect)
            .blur(radius: radius)
            .padding([.horizontal, .bottom], -radius * 2)
            .padding(.top, -radius / 2)
            /// Only Visible for scaled screenshots!
            .opacity(items[currentIndex].zoomScale > 1 ? 1 : 0)
            .ignoresSafeArea()
    }

    var deviceCornerRadius: CGFloat {
        if let imageSize = items.first?.screenshot?.size {
            let ratio = screenshotSize.height / imageSize.height
            let actualCornerRadius: CGFloat = 180
            return actualCornerRadius * ratio
        }

        return 0
    }

    struct Item: Identifiable, Hashable {
        var id: Int
        var title: String
        var subtitle: String
        var screenshot: UIImage?
        var zoomScale: CGFloat = 1
        var zoomAnchor: UnitPoint = .center
    }

    /// Customize it according to your needs!
    var animation: Animation {
        .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }
}

// MARK: - OnboardingView (použití z ProvikartApp – stejný obsah jako původní ContentView ukázka)

struct OnboardingView: View {
    var onFinish: () -> Void

    var body: some View {
        iOS26StyleOnBoarding(tint: .blue, hideBezels: false, items: [
            .init(
                id: 0,
                title: "Vítejte v ProviKart",
                subtitle: "Představujeme nový způsob hlídání provizí a objednávek pomocí AI",
                screenshot: UIImage(named: "Screen1")
            ),
            .init(
                id: 1,
                title: "Kalendář Instalací",
                subtitle: "Přehledný kalendář, ve kterém vidíte přesně kdy se vám co spuští",
                screenshot: UIImage(named: "Screen2")
            ),
            .init(
                id: 2,
                title: "Nativní Aplikace",
                subtitle: "Nejmodernější a nativní aplikace",
                screenshot: UIImage(named: "Screen4"),
                zoomScale: 1.5,
                zoomAnchor: .init(x: 0.5, y: 1.1)
            ),
            .init(
                id: 3,
                title: "AI Rozpoznání",
                subtitle: "Díky AI automaticky aplikace rozpozná text objednávky a ušetří vám tak dost času.",
                screenshot: UIImage(named: "Screen3"),
                zoomScale: 1.3,
                zoomAnchor: .init(x: 0.5, y: -0.3)
            ),
            .init(
                id: 4,
                title: "Notifikace",
                subtitle: "Povolte notifikace, abyste nepromeškali důležité připomínky k provizím a objednávkám.",
                screenshot: UIImage(named: "Screen6"),
            ),
            .init(
                id: 5,
                title: "Face ID / Touch ID",
                subtitle: "Kvůli citlivosti dat vás budeme ověřovat. Potřebujeme svolení k použití FACE ID",
                screenshot: UIImage(named: "Screen7"),
            ),
            .init(
                id: 6,
                title: "Moderní Widgety",
                subtitle: "Aplikace obsahuje widgety, kvůli důležitosti zobrazení informací.",
                screenshot: UIImage(named: "Screen5")
            )
        ], stepAction: { index, advance in
            if index == 4 {
                requestNotificationPermission(then: advance)
            } else if index == 5 {
                requestBiometricPermission(then: advance)
            } else {
                advance()
            }
        }) {
            onFinish()
        }
    }

    /// Zobrazí výzvu k ověření Face ID / Touch ID. Na další stránku pustí jen po úspěšném ověření; při zrušení nebo chybě zůstane uživatel na kroku Face ID.
    private func requestBiometricPermission(then advance: @escaping () -> Void) {
        let context = LAContext()
        var biometricError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError) else {
            // Biometrika není k dispozici – přesto pustíme dál (např. simulátor)
            advance()
            return
        }
        let reason = "Provikart používá Face ID pro rychlé a bezpečné ověření při návratu do aplikace."
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                if success {
                    advance()
                }
                // Při !success (zrušení / neúspěch) nevoláme advance() – uživatel zůstane na Face ID kroku
            }
        }
    }

    /// Vyžádá svolení k notifikacím – zobrazí systémový dialog. Po odpovědi (povolení i zamítnutí) pustí na další krok.
    private func requestNotificationPermission(then advance: @escaping () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    UserDefaults.standard.set(true, forKey: "Provikart.notificationsEnabled")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    UserDefaults.standard.set(false, forKey: "Provikart.notificationsEnabled")
                }
                advance()
            }
        }
    }
}
#Preview("Onboarding") {
    OnboardingView(onFinish: {})
}

