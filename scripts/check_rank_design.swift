import Foundation
import ImageIO
import CoreGraphics

@main
struct RankDesignChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            checks += 1
        }
        for rank in 1...9 {
            let lower = RankProgress.thresholds[rank - 1]
            let upper = RankProgress.thresholds[rank]
            check(RankProgress.fraction(followers: lower, rank: rank) == 0, "Rank \(rank) begins at zero")
            check(RankProgress.fraction(followers: upper, rank: rank) == 1, "Rank \(rank) completes at next threshold")
            check(RankProgress.fraction(followers: lower - 1, rank: rank) == 0, "Clamp below rank \(rank)")
            check(RankProgress.fraction(followers: upper + 1, rank: rank) == 1, "Clamp above rank \(rank)")
        }
        check(abs(RankProgress.fraction(followers: 1_482, rank: 3) - 982.0 / 1_500.0) < 0.00001, "Mockup rank 3 progress")
        check(RankProgress.fraction(followers: 20_000_000, rank: 10) == 1, "Maximum rank")
        check(RankProgress.fraction(followers: Int.min, rank: 3) == 0, "No negative overflow")
        check(RankProgress.fraction(followers: Int.max, rank: 3) == 1, "No positive overflow")
        check(RankProgress.fraction(followers: 0, rank: Int.min) == 0, "Clamp invalid rank")

        let url = URL(fileURLWithPath: "Assets.xcassets/RankIllustrations.imageset/rank-illustrations-v1.png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("Missing rank atlas")
        }
        check(atlas.alphaInfo != .none && atlas.alphaInfo != .noneSkipFirst && atlas.alphaInfo != .noneSkipLast, "Atlas alpha")
        for index in 0..<10 {
            let x0 = atlas.width * (index % 5) / 5
            let x1 = atlas.width * (index % 5 + 1) / 5
            let y0 = atlas.height * (index / 5) / 2
            let y1 = atlas.height * (index / 5 + 1) / 2
            guard let cell = atlas.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else {
                fatalError("Invalid rank cell \(index + 1)")
            }
            var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
            let context = CGContext(data: &bytes, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cell, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            let opaque = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 128 }.count
            let clear = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] < 16 }.count
            check(opaque > 180, "Rank \(index + 1) contains artwork")
            check(clear > 80, "Rank \(index + 1) has transparent padding")
        }
        print("PASS: \(checks) progress and artwork checks; atlas \(atlas.width)×\(atlas.height), 10 sprites.")
    }
}
