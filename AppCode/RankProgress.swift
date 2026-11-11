import Foundation

enum RankProgress {
    static let thresholds = [0, 100, 500, 2_000, 10_000, 50_000, 200_000, 1_000_000, 5_000_000, 20_000_000]

    static func fraction(followers: Int, rank: Int) -> Double {
        let index = min(10, max(1, rank)) - 1
        guard index < 9 else { return 1 }
        let lower = Double(thresholds[index])
        let upper = Double(thresholds[index + 1])
        return min(1, max(0, (Double(followers) - lower) / (upper - lower)))
    }
}
