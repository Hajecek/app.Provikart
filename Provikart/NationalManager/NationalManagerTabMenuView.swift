//
//  NationalManagerTabMenuView.swift
//  Provikart
//
//  Spodní menu národního manažera: Přehled, Nahlášené lokality, Aika (uprostřed,
//  živá koule), Lokality a Kontrola objednávek.
//

import SwiftUI
import UIKit

enum NationalManagerTabs: Hashable {
    case dashboard
    case localities
    case aika
    case locations
    case orders
}

struct NationalManagerTabMenuView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @State private var selectedTab: NationalManagerTabs = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Přehled", systemImage: "square.grid.2x2", value: .dashboard) {
                NationalDashboardView(openTab: { selectedTab = $0 })
                    .environmentObject(authState)
            }

            Tab("Nahlášené", systemImage: "mappin.and.ellipse", value: .locations) {
                NationalLocationsView()
                    .environmentObject(authState)
            }

            Tab(value: .aika) {
                NavigationStack {
                    // Hovor se spustí klepnutím na kouli a ukončí při odchodu ze záložky.
                    // Spodní menu se schová, zpět vede tlačítko „Domů“ v horní liště.
                    AikaView(onClose: { selectedTab = .dashboard })
                        .environmentObject(authState)
                }
            } label: {
                // Místo ikony prázdné místo – živou kouli do něj vloží TabBarAikaOrb.
                // Bez popisku, aby koule mohla být velká a přesně uprostřed lišty.
                Label {
                    Text("")
                } icon: {
                    Image(uiImage: TabBarAikaOrb.placeholderIcon)
                }
                .accessibilityLabel("Aika")
            }

            Tab("Lokality", systemImage: "map", value: .localities) {
                NationalLocalitiesView()
                    .environmentObject(authState)
            }

            Tab("Objednávky", systemImage: "list.clipboard", value: .orders) {
                NationalIncompleteOrdersView()
                    .environmentObject(authState)
            }
        }
        .background(TabMenuSelectionColor(color: UIColor(red: 0.969, green: 0.737, blue: 0.329, alpha: 1)))
        .background(TabBarAikaOrb(itemIndex: 2, itemCount: 5))
        .modifier(LoginApprovalBottomAccessoryModifier(
            approvalState: appLoginApprovalState,
            showsPhoto: false,
            photoEnabled: false,
            onTakePhoto: {}
        ))
    }
}

// MARK: - Živá koule Aiky ve spodní liště

/// Vloží animovanou kouli AIKA do lišty záložek nad ikonu položky `itemIndex`.
/// Koule nepřijímá dotyky, takže klepnutí jde dál na samotnou záložku.
struct TabBarAikaOrb: UIViewRepresentable {
    let itemIndex: Int
    let itemCount: Int

    static let orbSize: CGFloat = 48

    /// Průhledná ikona velikosti koule, aby lišta nechala místo a popisek byl na svém místě.
    static let placeholderIcon: UIImage = {
        let size = CGSize(width: 48, height: 28)
        let image = UIGraphicsImageRenderer(size: size).image { _ in }
        return image.withRenderingMode(.alwaysTemplate)
    }()

    func makeCoordinator() -> Coordinator { Coordinator(itemIndex: itemIndex, itemCount: itemCount) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            coordinator.attach(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        let itemIndex: Int
        let itemCount: Int
        private weak var tabBar: UITabBar?
        private var host: UIHostingController<AnyView>?
        private var displayLink: CADisplayLink?

        init(itemIndex: Int, itemCount: Int) {
            self.itemIndex = itemIndex
            self.itemCount = itemCount
        }

        func attach(from view: UIView) {
            guard tabBar == nil, let root = view.window?.rootViewController,
                  let controller = Self.findTabBarController(root) else { return }
            let bar = controller.tabBar
            tabBar = bar

            let orb = AikaOrbView(level: 0.35, glow: false, zoom: 0.66, spin: 1.8, fps: 24)
                .frame(width: TabBarAikaOrb.orbSize, height: TabBarAikaOrb.orbSize)
            let host = UIHostingController(rootView: AnyView(orb))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.frame = CGRect(x: 0, y: 0, width: TabBarAikaOrb.orbSize, height: TabBarAikaOrb.orbSize)
            host.view.accessibilityElementsHidden = true
            bar.addSubview(host.view)
            self.host = host

            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
            link.add(to: .main, forMode: .common)
            displayLink = link
            reposition()
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            host?.view.removeFromSuperview()
            host = nil
        }

        @objc private func tick() { reposition() }

        private func reposition() {
            guard let bar = tabBar, let orbView = host?.view else { return }
            if orbView.superview !== bar { bar.addSubview(orbView) }
            if bar.subviews.last !== orbView { bar.bringSubviewToFront(orbView) }

            let center = iconCenter(in: bar)
            let size = TabBarAikaOrb.orbSize
            let frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            if orbView.frame != frame { orbView.frame = frame }
        }

        /// Vodorovně přesně mezi viditelným obsahem (ikona + popisek) sousedních položek, aby
        /// byla mezera vlevo i vpravo od koule stejná – položky mají různou šířku podle popisků,
        /// takže střed tlačítka ani střed mezi krajními položkami nedá stejné mezery.
        /// Svisle střed prostřední položky.
        private func iconCenter(in bar: UITabBar) -> CGPoint {
            let buttons = Self.itemButtons(in: bar)
            if buttons.count == itemCount, itemIndex > 0, itemIndex < itemCount - 1 {
                let button = buttons[itemIndex]
                let frame = button.convert(button.bounds, to: bar)
                let left = Self.contentFrame(of: buttons[itemIndex - 1], in: bar)
                let right = Self.contentFrame(of: buttons[itemIndex + 1], in: bar)
                return CGPoint(x: (left.maxX + right.minX) / 2, y: frame.midY)
            }
            let height = bar.bounds.height - bar.safeAreaInsets.bottom
            return CGPoint(x: bar.bounds.midX, y: max(20, height * 0.42))
        }

        /// Tlačítka položek lišty seřazená zleva (soukromé třídy se mezi verzemi iOS liší).
        private static func itemButtons(in bar: UITabBar) -> [UIView] {
            var found: [UIView] = []
            func walk(_ view: UIView) {
                let name = NSStringFromClass(type(of: view))
                if name.contains("TabBarButton") || name.hasSuffix("TabButton") {
                    if view.bounds.width > 20 { found.append(view) }
                    return
                }
                view.subviews.forEach(walk)
            }
            walk(bar)
            // Ve více vrstvách (sklo / výběr) se tlačítka můžou opakovat – nech jedno na pozici.
            var unique: [UIView] = []
            for view in found.sorted(by: { $0.convert($0.bounds, to: bar).midX < $1.convert($1.bounds, to: bar).midX }) {
                let midX = view.convert(view.bounds, to: bar).midX
                if let last = unique.last, abs(last.convert(last.bounds, to: bar).midX - midX) < 8 { continue }
                unique.append(view)
            }
            return unique
        }

        /// Rámeček viditelného obsahu tlačítka (popisky a ikony); když nic nenajde, celé tlačítko.
        private static func contentFrame(of button: UIView, in bar: UIView) -> CGRect {
            var union = CGRect.null
            func walk(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0.01 else { return }
                if let label = view as? UILabel, !(label.text ?? "").isEmpty, label.bounds.width > 1 {
                    let textRect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: 1)
                    union = union.union(label.convert(textRect, to: bar))
                } else if let image = view as? UIImageView, image.image != nil, image.bounds.width > 1 {
                    union = union.union(image.convert(image.bounds, to: bar))
                }
                view.subviews.forEach(walk)
            }
            walk(button)
            return union.isNull ? button.convert(button.bounds, to: bar) : union
        }


        private static func findTabBarController(_ vc: UIViewController) -> UITabBarController? {
            if let tab = vc as? UITabBarController { return tab }
            for child in vc.children {
                if let found = findTabBarController(child) { return found }
            }
            if let presented = vc.presentedViewController {
                return findTabBarController(presented)
            }
            return nil
        }
    }
}
