//
//  ManagerWebTheme.swift
//  Provikart
//
//  Vzhled manažerské části shodný s webem (--sv-* proměnné, .cb-mesh pozadí, skleněné karty).
//

import SwiftUI

/// Mesh pozadí jako `.cb-mesh` na webu (světlá a tmavá varianta).
struct ManagerMeshBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(
                    colors: isDark
                        ? [Color(webHex: "#3c4957"), Color(webHex: "#2c3135"), Color(webHex: "#33281f")]
                        : [Color(webHex: "#d7e3ec"), Color(webHex: "#e4e6df"), Color(webHex: "#e2d8ca")],
                    startPoint: .top, endPoint: .bottom
                )
                blob(isDark ? "#5e7286" : "#c6dcef", x: 0.20, y: 0.02, r: w * 0.85)
                blob(isDark ? "#4b5866" : "#d5e2ec", x: 0.86, y: 0.06, r: w * 0.70)
                blob(isDark ? "#3a3d3e" : "#e6dccb", x: 0.50, y: 0.58, r: w * 0.95)
                blob(isDark ? "#33402f" : "#cbd8c0", x: 0.05, y: 0.94, r: w * 0.70)
                blob(isDark ? "#7a4c2f" : "#e7cdb6", x: 0.80, y: 1.02, r: w * 0.85)
                (isDark
                    ? Color(red: 0.03, green: 0.043, blue: 0.039).opacity(0.46)
                    : Color(red: 0.94, green: 0.953, blue: 0.933).opacity(0.62))
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    private func blob(_ hex: String, x: CGFloat, y: CGFloat, r: CGFloat) -> some View {
        RadialGradient(
            colors: [Color(webHex: hex), .clear],
            center: UnitPoint(x: x, y: y),
            startRadius: 0,
            endRadius: r
        )
    }
}

/// Výplň skleněné karty (`--sv-glass`), závislá na světlém/tmavém režimu.
struct ManagerGlassFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorScheme == .dark
            ? Color(red: 0.078, green: 0.09, blue: 0.09).opacity(0.62)
            : Color.white.opacity(0.62)
    }
}

/// Logo v horní liště manažerských obrazovek.
struct ManagerToolbarLogo: View {
    var body: some View {
        ProvikartBrandLogoView(style: .large)
            .fixedSize()
    }
}

/// Webová paleta (--sv-*), adaptivní podle světlého/tmavého režimu.
enum SV {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let coral = dyn(0xF27D5F, 0xFF9A7C)
    static let lime = dyn(0xA9D636, 0xCDF06A)
    static let sky = dyn(0x5AA6EC, 0x8CC4FF)
    static let good = dyn(0x3C7A14, 0xB8E65A)
    static let bad = dyn(0xB8401F, 0xFF9A7C)
    static let accent = Color(red: 0.99, green: 0.745, blue: 0.19)
    static let ink = Color(red: 0.075, green: 0.09, blue: 0.10)
    /// Aktivní „pilulka“ segmentů (tmavá ve světlém, šedá v tmavém režimu).
    static let pill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.345, green: 0.37, blue: 0.365, alpha: 0.74)
            : UIColor(red: 0.075, green: 0.09, blue: 0.10, alpha: 1)
    })
    static let onPill = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let rim = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.15)
            : UIColor(white: 1, alpha: 0.72)
    })
}

/// Skleněná karta jako `.sv-card` na webu: blur, sklo, světlý okraj, stín.
struct SVCardBackground: View {
    var radius: CGFloat = 22
    var tint: Color = .clear

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(ManagerGlassFill())
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SV.rim)
            }
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

/// Štítek jako `.sv-badge` / `.ov-chip`.
struct SVChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .secondary
    var textColor: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .heavy)) }
            Text(text).font(.caption.weight(.bold))
        }
        .foregroundStyle(textColor ?? tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.30)))
    }
}

extension Color {
    init(webHex hex: String) {
        var raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
