import AppKit
import SimpleVectorizerCore
import SwiftUI

/// The dark palette of the Simple family (SimpleAudio, SimpleScanner, SimplePJ, SimpleSKP, Montage, OSCScore).
enum Theme {
    static let background = NSColor(hex: 0x111317)
    static let panel = NSColor(hex: 0x16191E)
    static let lane = NSColor(hex: 0x181B21)
    static let laneAlt = NSColor(hex: 0x1B1F26)
    static let laneSelected = NSColor(hex: 0x1F2530)
    static let header = NSColor(hex: 0x14171C)
    static let separator = NSColor(hex: 0x0B0C0F)
    static let gridMinor = NSColor(white: 1, alpha: 0.035)
    static let gridMajor = NSColor(white: 1, alpha: 0.085)
    static let text = NSColor(hex: 0xE6E8EC)
    static let textDim = NSColor(hex: 0x8A919E)
    static let textFaint = NSColor(hex: 0x565D6A)
    static let accent = NSColor(hex: 0xFFB454)
    static let alive = NSColor(hex: 0x9ECE6A)
    static let standby = NSColor(hex: 0x7AA2F7)
    static let tcp = NSColor(hex: 0x5CE1E6)
    static let osc = NSColor(hex: 0xC792EA)
    static let warning = NSColor(hex: 0xF2D96B)
    static let danger = NSColor(hex: 0xFF5C57)
    static let selection = NSColor.white

    static let penColors: [NSColor] = [
        accent, // Pen 1 — Amber FFB454
        tcp,    // Pen 2 — Cyan 5CE1E6
        osc,    // Pen 3 — Purple C792EA
        alive,  // Pen 4 — Green 9ECE6A
    ]

    static func penColor(_ index: Int) -> NSColor {
        penColors[max(0, index) % penColors.count]
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xff) / 255,
            green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    var swiftUI: Color { Color(nsColor: self) }
}

enum Format {
    static func decimal(_ value: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", value)
        return Localization.isEnglish ? s : s.replacingOccurrences(of: ".", with: ",")
    }

    static func distanceMM(_ mm: Double) -> String {
        guard mm.isFinite, mm > 0 else { return "0 mm" }
        if mm >= 1000 {
            return "\(decimal(mm / 1000.0, digits: 2)) m"
        }
        return "\(Int(mm.rounded())) mm"
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total) s"
        }
        let m = total / 60
        let s = total % 60
        return String(format: "%d min %02d s", m, s)
    }

    static func latency(_ ms: Double?) -> String {
        guard let ms, ms.isFinite else { return "—" }
        if ms < 10 { return "\(decimal(ms, digits: 1)) ms" }
        return String(format: "%.0f ms", ms)
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) " + (n > 1 ? (plural ?? singular + "s") : singular)
    }
}
