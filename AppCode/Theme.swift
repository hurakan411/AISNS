import SwiftUI
import UIKit

/// Offline fixtures are opt-in and available only in Debug simulator builds.
enum DesignPreview {
    static var isActive: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        false
        #endif
    }

    static func argument(_ key: String) -> String? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.arguments.first { $0.hasPrefix(key + "=") }?
            .dropFirst(key.count + 1).description
    }
}

enum AppDesignTemplate: String, CaseIterable, Identifiable {
    case black, white, lofi
    static let storageKey = "appDesignTemplate"
    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .white ? .light : .dark }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .black
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.storageKey) }
}

private struct DesignTemplateKey: EnvironmentKey {
    static let defaultValue: AppDesignTemplate = .black
}
extension EnvironmentValues {
    var designTemplate: AppDesignTemplate {
        get { self[DesignTemplateKey.self] }
        set { self[DesignTemplateKey.self] = newValue }
    }
}

struct Theme {
    // One shared user preference; environment readers invalidate decorative leaf views.
    static var activeTemplate = AppDesignTemplate.load()
    // Dynamic colors follow the selected template in both SwiftUI and UIKit controls.
    static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
    private static let base_textPrimary = adaptive(dark: .white, light: UIColor(red: 0.13, green: 0.09, blue: 0.18, alpha: 1))
    static var surfaceHighlight: Color { textPrimary }
    static var onAccent: Color { activeTemplate == .lofi ? bgDeepBlack : .white }
    private static let base_inactiveTab = adaptive(dark: UIColor.gray.withAlphaComponent(0.5),
                                     light: UIColor(red: 0.43, green: 0.40, blue: 0.47, alpha: 1))
    private static let base_bgDeepBlack = adaptive(
        dark: UIColor(red: 0.008, green: 0.006, blue: 0.018, alpha: 1),
        light: UIColor(red: 0.985, green: 0.977, blue: 0.995, alpha: 1))
    private static let base_hotPink = adaptive(
        dark: UIColor(red: 0.925, green: 0.282, blue: 0.6, alpha: 1),
        light: UIColor(red: 0.76, green: 0.10, blue: 0.40, alpha: 1))
    private static let base_deepPurple = adaptive(
        dark: UIColor(red: 0.105, green: 0.063, blue: 0.18, alpha: 1),
        light: UIColor(red: 0.93, green: 0.90, blue: 0.97, alpha: 1))
    private static let base_purpleAccent = Color(red: 0.435, green: 0.263, blue: 0.71)
    private static let base_lavender = adaptive(
        dark: UIColor(red: 0.67, green: 0.49, blue: 0.88, alpha: 1),
        light: UIColor(red: 0.44, green: 0.25, blue: 0.65, alpha: 1))
    // 既存画面の補助色は互換性を保ちつつ、シアンから紫へ統一する。
    static var cyan: Color { purpleAccent }
    private static let base_cardBackground = adaptive(
        dark: UIColor(red: 0.052, green: 0.045, blue: 0.075, alpha: 1), light: .white)
    private static let base_aiCardBackground = adaptive(
        dark: UIColor(red: 0.075, green: 0.052, blue: 0.12, alpha: 1),
        light: UIColor(red: 0.96, green: 0.94, blue: 0.985, alpha: 1))
    private static let base_modalBackground = adaptive(dark: .black, light: .white)
    private static let base_conversationBackground = adaptive(
        dark: UIColor(red: 0.13, green: 0.09, blue: 0.18, alpha: 1),
        light: UIColor(red: 0.98, green: 0.96, blue: 1, alpha: 1))
    private static let base_insetBackground = adaptive(dark: .black, light: UIColor(red: 0.88, green: 0.83, blue: 0.94, alpha: 1))
    static var textPrimary: Color { activeTemplate == .lofi ? Color(red: 0.96, green: 0.91, blue: 0.87) : base_textPrimary }
    static var inactiveTab: Color { activeTemplate == .lofi ? Color(red: 0.67, green: 0.59, blue: 0.67) : base_inactiveTab }
    static var bgDeepBlack: Color { activeTemplate == .lofi ? Color(red: 0.085, green: 0.066, blue: 0.10) : base_bgDeepBlack }
    static var hotPink: Color { activeTemplate == .lofi ? Color(red: 0.91, green: 0.61, blue: 0.71) : base_hotPink }
    static var deepPurple: Color { activeTemplate == .lofi ? Color(red: 0.21, green: 0.15, blue: 0.23) : base_deepPurple }
    static var purpleAccent: Color { activeTemplate == .lofi ? Color(red: 0.65, green: 0.49, blue: 0.73) : base_purpleAccent }
    static var lavender: Color { activeTemplate == .lofi ? Color(red: 0.77, green: 0.65, blue: 0.82) : base_lavender }
    static var cardBackground: Color { activeTemplate == .lofi ? Color(red: 0.18, green: 0.135, blue: 0.195) : base_cardBackground }
    static var aiCardBackground: Color { activeTemplate == .lofi ? Color(red: 0.20, green: 0.15, blue: 0.22) : base_aiCardBackground }
    static var modalBackground: Color { activeTemplate == .lofi ? bgDeepBlack : base_modalBackground }
    static var conversationBackground: Color { activeTemplate == .lofi ? cardBackground : base_conversationBackground }
    static var insetBackground: Color { activeTemplate == .lofi ? deepPurple : base_insetBackground }
    static var subtleBorder: Color { activeTemplate == .lofi ? lavender.opacity(0.48) : purpleAccent.opacity(0.24) }
    static var accentGradient: LinearGradient { LinearGradient(
        colors: [hotPink, purpleAccent, lavender],
        startPoint: .leading,
        endPoint: .trailing
    ) }
    
    static let defaultAvatarAsset = "UPMEMascot"
    static let fallbackImg = "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=1000"
}

extension View {
    func neonShadow(color: Color = Theme.hotPink, radius: CGFloat = 10) -> some View {
        modifier(TemplateShadow(color: color, radius: radius))
    }

}

private struct TemplateShadow: ViewModifier {
    @Environment(\.designTemplate) private var template
    let color: Color
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(template == .lofi ? 0.18 : 0.42),
                       radius: template == .lofi ? 0 : radius,
                       x: template == .lofi ? 2 : 0, y: template == .lofi ? 2 : 0)
    }
}

/// Statistics keep their own surface treatments while following the selected template.
enum StatsTheme {
    static var bgDeepBlack: Color { Theme.bgDeepBlack }
    static var hotPink: Color { Theme.hotPink }
    static var purpleAccent: Color { Theme.purpleAccent }
    static var lavender: Color { Theme.lavender }
    static var cyan: Color { Theme.cyan }
    static var secondaryText: Color { Theme.activeTemplate == .lofi ? Theme.textPrimary.opacity(0.7) : Theme.adaptive(
        dark: UIColor(red: 0.65, green: 0.62, blue: 0.69, alpha: 1),
        light: UIColor(red: 0.40, green: 0.36, blue: 0.45, alpha: 1)) }
    static var surfaceGradient: LinearGradient { LinearGradient(
        colors: [Theme.adaptive(dark: UIColor(red: 0.155, green: 0.115, blue: 0.190, alpha: 1),
                                light: UIColor(red: 0.99, green: 0.98, blue: 1, alpha: 1)),
                 Theme.adaptive(dark: UIColor(red: 0.105, green: 0.080, blue: 0.140, alpha: 1), light: .white),
                 Theme.adaptive(dark: UIColor(red: 0.160, green: 0.095, blue: 0.165, alpha: 1),
                                light: UIColor(red: 1, green: 0.95, blue: 0.98, alpha: 1))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    ) }
}

/// Code-native pixel artwork: no downloads, extra image library or per-user assets.
struct PixelPanel: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(4.0, r.width / 8, r.height / 8)
        let points = [(2*s, 0.0), (r.width-2*s, 0), (r.width-2*s, s), (r.width-s, s),
                      (r.width-s, 2*s), (r.width, 2*s), (r.width, r.height-2*s),
                      (r.width-s, r.height-2*s), (r.width-s, r.height-s), (r.width-2*s, r.height-s),
                      (r.width-2*s, r.height), (2*s, r.height), (2*s, r.height-s), (s, r.height-s),
                      (s, r.height-2*s), (0, r.height-2*s), (0, 2*s), (s, 2*s), (s, s), (2*s, s)]
        var p = Path()
        for (i, point) in points.enumerated() {
            let pt = CGPoint(x: r.minX + point.0, y: r.minY + point.1)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct TemplateAvatarShape: Shape {
    var pixel: Bool
    func path(in rect: CGRect) -> Path { pixel ? PixelPanel().path(in: rect) : Circle().path(in: rect) }
}

struct TemplateCardClip: Shape {
    var pixel: Bool
    var cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        pixel ? PixelPanel().path(in: rect) : RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}

enum PixelPatterns {
    static func rows(for name: String) -> [String]? {
        switch name {
        case "heart", "heart.fill": return ["01100110","11111111","11111111","11111111","01111110","00111100","00011000"]
        case "house.fill": return ["00011000","00111100","01111110","11111111","01111110","01100110","01100110","01100110"]
        case "plus.app.fill", "plus", "plus.square.fill": return ["11111111","10011001","10011001","11111111","11111111","10011001","10011001","11111111"]
        case "chart.bar.fill": return ["00000011","00000011","00011011","00011011","11011011","11011011","11011011","11011011"]
        case "person.fill": return ["00011000","00111100","00111100","00011000","00000000","00111100","01111110","11111111"]
        case "gearshape.fill": return ["00011000","01111110","01100110","11000011","11000011","01100110","01111110","00011000"]
        case "bubble.right.fill", "bubble.left", "bubble.left.fill", "bubble.left.and.bubble.right":
            return ["11111111","10000001","10101001","10000001","11111111","00110000","00100000"]
        case "star", "star.fill", "star.circle", "star.circle.fill": return ["000010000","000111000","111111111","011111110","001111100","011101110","011000110"]
        case "pencil", "pencil.line", "pencil.circle.fill": return ["00000110","00001111","00011110","00111100","01111000","11110000","11100000","11000000"]
        case "arrowshape.turn.up.left.circle": return ["00010000","00110000","01111110","11111111","01110011","00110011","00010011"]
        case "crown": return ["100010001","110111011","111111111","011111110","011111110","000000000","011111110"]
        case "megaphone": return ["000000001100","000000111100","000011111100","001111111100","111111111100","111111111100","001111111100","000011111100","000011001100","000011000000","000011000000"]
        case "wordmark": return ["100010111100100010111110100","100010100010110110100000100","100010100010101010100000100","100010111100101010111100100","100010100000100010100000100","100010100000100010100000000","011100100000100010111110100"]
        default: return nil
        }
    }
}

struct PixelGlyph: Shape {
    let name: String
    func path(in rect: CGRect) -> Path {
        guard let rows = PixelPatterns.rows(for: name), let columns = rows.map(\.count).max(), columns > 0 else { return Path() }
        let unit = min(rect.width / CGFloat(columns), rect.height / CGFloat(rows.count))
        let x = rect.midX - CGFloat(columns) * unit / 2
        let y = rect.midY - CGFloat(rows.count) * unit / 2
        var p = Path()
        for (row, cells) in rows.enumerated() {
            for (column, cell) in cells.enumerated() where cell == "1" {
                p.addRect(CGRect(x: x + CGFloat(column)*unit, y: y + CGFloat(row)*unit, width: unit, height: unit))
            }
        }
        return p
    }
}

struct TemplateIcon: View {
    @Environment(\.designTemplate) private var template
    let systemName: String
    var size: CGFloat = 16
    var body: some View {
        if template == .lofi, PixelPatterns.rows(for: systemName) != nil {
            PixelGlyph(name: systemName).fill(.foreground, style: FillStyle(antialiased: false))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemName)
        }
    }
}

struct DefaultProfileArtwork: View {
    @Environment(\.designTemplate) private var template
    private let rows = ["................", "......oooo......", "....oooooooo....", "...oooooooooo...",
                        "...ooxooooxoo...", "...ooxooooxoo...", "..oooooooooooo..", "..ooopooopoooo..",
                        "..oooooxxooooo..", ".oooooooooooooo.", ".ooooppoppooooo.", ".ooopppppppoooo.",
                        ".oooopppppooooo.", ".ooooopppoooooo.", ".ooooolploooooo.", "..ooo..oo..ooo.."]
    var body: some View {
        if template == .lofi {
            Canvas { context, size in
                let unit = min(size.width, size.height) / 16
                let origin = CGPoint(x: (size.width-unit*16)/2, y: (size.height-unit*16)/2)
                for (r, row) in rows.enumerated() {
                    for (c, cell) in row.enumerated() where cell != "." {
                        let color: Color = cell == "o" ? Theme.textPrimary : cell == "p" ? Theme.hotPink : cell == "l" ? Theme.lavender : Theme.bgDeepBlack
                        context.fill(Path(CGRect(x: origin.x+CGFloat(c)*unit, y: origin.y+CGFloat(r)*unit, width: unit, height: unit)),
                                     with: .color(color), style: FillStyle(antialiased: false))
                    }
                }
            }
            .accessibilityHidden(true)
        } else { Image(Theme.defaultAvatarAsset).resizable().scaledToFill() }
    }
}

struct PixelProgressRing: Shape {
    var progress: Double = 1
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        guard diameter > 0, progress.isFinite else { return Path() }
        let count = min(80, max(0, Int(ceil(min(1, max(0, progress)) * 80))))
        let unit = diameter / 50
        let radius = diameter / 2 - unit * 2
        var p = Path()
        for i in 0..<count {
            let angle = Double(i) / 80 * .pi * 2 - .pi / 2
            let x = (rect.midX + CGFloat(cos(angle))*radius) / unit
            let y = (rect.midY + CGFloat(sin(angle))*radius) / unit
            p.addRect(CGRect(x: x.rounded()*unit-unit, y: y.rounded()*unit-unit, width: unit*2, height: unit*2))
        }
        return p
    }
}

/// The image fills an already-sized slot, so its aspect ratio cannot widen a card.
struct PostAttachmentImage: View {
    let image: UIImage
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct TactileHeader: View {
    let title: LocalizedStringKey
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 16)
            Text("UPME")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accentGradient)
                .accessibilityLabel("UPME! | AI SNS")
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }
}

struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// The generated atlas has ten equal cells, five across and two down.
/// Cropping happens once in memory, not on every SwiftUI render.
private enum RankArtworkCache {
    static let images: [UIImage] = {
        guard let atlas = UIImage(named: "RankIllustrations")?.cgImage else { return [] }
        return (0..<10).compactMap { index in
            let x0 = atlas.width * (index % 5) / 5
            let x1 = atlas.width * (index % 5 + 1) / 5
            let y0 = atlas.height * (index / 5) / 2
            let y1 = atlas.height * (index / 5 + 1) / 2
            guard let cell = atlas.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
            return UIImage(cgImage: cell)
        }
    }()
}

struct RankArtwork: View {
    @Environment(\.designTemplate) private var template
    let rank: Int
    var body: some View {
        let index = min(10, max(1, rank)) - 1
        Group {
            if template == .lofi {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    ZStack {
                        PixelGlyph(name: rank <= 3 ? "megaphone" : rank <= 6 ? "star" : "crown")
                            .fill(Theme.lavender, style: FillStyle(antialiased: false))
                            .frame(width: side * 0.63, height: side * 0.63)
                        PixelGlyph(name: "heart").fill(Theme.hotPink, style: FillStyle(antialiased: false))
                            .frame(width: side * 0.23, height: side * 0.23).offset(x: side * 0.27, y: -side * 0.29)
                        PixelGlyph(name: "heart").fill(Theme.hotPink.opacity(0.7), style: FillStyle(antialiased: false))
                            .frame(width: side * 0.13, height: side * 0.13).offset(x: side * 0.34, y: -side * 0.04)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else if RankArtworkCache.images.count == 10 {
                Image(uiImage: RankArtworkCache.images[index])
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "heart.bubble.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.accentGradient)
                    .padding(24)
            }
        }
        .accessibilityHidden(true)
    }
}

struct RankProgressRing: View {
    let rank: Int
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.designTemplate) private var template

    var body: some View {
        ZStack {
            if template == .lofi {
                PixelProgressRing().fill(Theme.lavender.opacity(0.3), style: FillStyle(antialiased: false))
                PixelProgressRing(progress: progress).fill(Theme.hotPink, style: FillStyle(antialiased: false))
            } else {
            Circle().stroke(Theme.purpleAccent.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(AngularGradient(colors: [Theme.hotPink, Theme.purpleAccent], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: progress)
            }
            GeometryReader { geometry in
                RankArtwork(rank: rank)
                    .padding(max(6, geometry.size.width * 0.085))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locale.identifier.hasPrefix("ja") ? "ランク \(rank)" : "Rank \(rank)")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
