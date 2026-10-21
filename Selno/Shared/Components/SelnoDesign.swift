import SwiftUI
import AppKit

enum SelnoDesign {
    static func adaptiveColor(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        adaptiveColor(light, dark)
    }
    static let canvas = adaptive(0xF4F5F1, 0x222925)
    static let sidebar = adaptive(0xE9EDE6, 0x26302A)
    static let surface = adaptive(0xFDFDF9, 0x2D3730)
    static let elevated = adaptive(0xFFFFFF, 0x364139)
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = adaptive(0x666E64, 0xADB8AB)
    static let border = adaptive(0xCFD6CB, 0x556250)
    static let accent = adaptive(0x3F6852, 0xA8C7A1)
    static let accentSecondary = adaptive(0x546D79, 0xADC7CF)
    static let success = adaptive(0x34654B, 0xA1CCA4)
    static let warning = adaptive(0x8B581A, 0xE8C38D)
    static let danger = adaptive(0xA33E3C, 0xECA5A0)
    static let radius: CGFloat = 11
    static let inset: CGFloat = 16
}

struct SelnoButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(primary ? SelnoDesign.canvas : SelnoDesign.accent)
            .background(primary ? SelnoDesign.accent : SelnoDesign.accent.opacity(configuration.isPressed ? 0.18 : hovering ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.75 : hovering && primary ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

struct StatusBadge: View {
    let title: String
    var symbol = "circle.dotted"
    var body: some View {
        Label(title, systemImage: symbol).font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(SelnoDesign.accent.opacity(0.1), in: Capsule()).foregroundStyle(SelnoDesign.accent)
    }
}
