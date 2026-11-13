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

struct Theme {
    static let bgDeepBlack = Color(red: 0.008, green: 0.006, blue: 0.018)
    static let hotPink = Color(red: 0.925, green: 0.282, blue: 0.6)
    static let deepPurple = Color(red: 0.105, green: 0.063, blue: 0.18)
    static let purpleAccent = Color(red: 0.435, green: 0.263, blue: 0.71)
    static let lavender = Color(red: 0.67, green: 0.49, blue: 0.88)
    // 既存画面の補助色は互換性を保ちつつ、シアンから紫へ統一する。
    static let cyan = purpleAccent
    static let cardBackground = Color(red: 0.052, green: 0.045, blue: 0.075)
    static let aiCardBackground = Color(red: 0.075, green: 0.052, blue: 0.12)
    static let subtleBorder = purpleAccent.opacity(0.24)
    static let accentGradient = LinearGradient(
        colors: [hotPink, purpleAccent, lavender],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let defaultAvatarAsset = "UPMEMascot"
    static let fallbackImg = "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=1000"
}

extension View {
    func neonShadow(color: Color = Theme.hotPink, radius: CGFloat = 10) -> some View {
        self.shadow(color: color.opacity(0.42), radius: radius, x: 0, y: 0)
    }

}

/// Keep the approved statistics surfaces independent of the restored app palette.
enum StatsTheme {
    static let bgDeepBlack = Theme.bgDeepBlack
    static let hotPink = Theme.hotPink
    static let purpleAccent = Theme.purpleAccent
    static let lavender = Theme.lavender
    static let cyan = Theme.cyan
    static let secondaryText = Color(red: 0.65, green: 0.62, blue: 0.69)
    static let surfaceGradient = LinearGradient(
        colors: [Color(red: 0.155, green: 0.115, blue: 0.190),
                 Color(red: 0.105, green: 0.080, blue: 0.140),
                 Color(red: 0.160, green: 0.095, blue: 0.165)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
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
                .foregroundStyle(.white)
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
    let rank: Int
    var body: some View {
        let index = min(10, max(1, rank)) - 1
        Group {
            if RankArtworkCache.images.count == 10 {
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

    var body: some View {
        ZStack {
            Circle().stroke(Theme.purpleAccent.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(AngularGradient(colors: [Theme.hotPink, Theme.purpleAccent], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: progress)
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
