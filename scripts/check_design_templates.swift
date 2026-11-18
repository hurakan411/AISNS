// Compile after Theme.swift for an iOS simulator and run via simctl spawn.
import Foundation
import SwiftUI
import UIKit

let suite = "UPME.design.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
precondition(AppDesignTemplate.load(from: defaults) == .black)
AppDesignTemplate.white.save(to: defaults)
precondition(AppDesignTemplate.load(from: defaults) == .white)
AppDesignTemplate.black.save(to: defaults)
precondition(AppDesignTemplate.load(from: defaults) == .black)
defaults.set("unknown-future-template", forKey: AppDesignTemplate.storageKey)
precondition(AppDesignTemplate.load(from: defaults) == .black)
precondition(AppDesignTemplate.black.colorScheme == .dark)
precondition(AppDesignTemplate.white.colorScheme == .light)
AppDesignTemplate.lofi.save(to: defaults)
precondition(AppDesignTemplate.load(from: defaults) == .lofi)
precondition(AppDesignTemplate.lofi.colorScheme == .dark)
Theme.activeTemplate = .black

func components(_ color: Color, _ style: UIUserInterfaceStyle) -> [CGFloat] {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    precondition(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
    return [r, g, b]
}
func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
    let linear = components(color, style).map { value -> Double in
        let c = Double(value)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
}
func contrast(_ foreground: Color, _ background: Color, _ style: UIUserInterfaceStyle) -> Double {
    let a = luminance(foreground, style), b = luminance(background, style)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
let blackBackground = components(Theme.bgDeepBlack, .dark)
precondition(abs(blackBackground[0] - 0.008) < 0.001, "Existing black palette changed")
precondition(luminance(Theme.bgDeepBlack, .light) > 0.9)
for style in [UIUserInterfaceStyle.dark, .light] {
    for surface in [Theme.bgDeepBlack, Theme.cardBackground, Theme.aiCardBackground,
                    Theme.modalBackground, Theme.conversationBackground] {
        precondition(contrast(Theme.textPrimary, surface, style) >= 7, "Body text contrast")
    }
}
for accent in [Theme.hotPink, Theme.lavender, Theme.purpleAccent] {
    precondition(contrast(accent, Theme.cardBackground, .light) >= 4.5, "White template accent contrast")
}
precondition(contrast(Theme.onAccent, Theme.hotPink, .light) >= 4.5)
precondition(contrast(Theme.inactiveTab, Theme.bgDeepBlack, .light) >= 4.5)
Theme.activeTemplate = .lofi
precondition(contrast(Theme.textPrimary, Theme.cardBackground, .dark) >= 7)
precondition(contrast(Theme.hotPink, Theme.cardBackground, .dark) >= 4.5)
precondition(contrast(Theme.onAccent, Theme.hotPink, .dark) >= 4.5)
for name in ["heart", "house.fill", "plus.app.fill", "chart.bar.fill", "person.fill", "gearshape.fill", "wordmark", "megaphone"] {
    precondition(PixelPatterns.rows(for: name) != nil)
    precondition(!PixelGlyph(name: name).path(in: CGRect(x: 0, y: 0, width: 24, height: 24)).isEmpty)
}
precondition(PixelProgressRing(progress: 0).path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
precondition(PixelProgressRing(progress: .nan).path(in: .zero).isEmpty)
precondition(PixelPanel().path(in: CGRect(x: 0, y: 0, width: 100, height: 60)).boundingRect.width == 100)
Theme.activeTemplate = .black
print("Design template checks passed: defaults, persistence, fallback, color schemes, palette and contrast")
