import SwiftUI

struct ParticleNetworkBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let particles: [NetworkParticle] = [
        .init(x: 0.04, y: 0.07, vx: 8.2, vy: 5.5, radius: 1.2, tint: .pink),
        .init(x: 0.16, y: 0.18, vx: -6.7, vy: 8.1, radius: 2.4, tint: .violet),
        .init(x: 0.29, y: 0.05, vx: 7.4, vy: 6.8, radius: 0.9, tint: .plum),
        .init(x: 0.43, y: 0.21, vx: -9.0, vy: 5.2, radius: 1.7, tint: .pink),
        .init(x: 0.58, y: 0.09, vx: 6.1, vy: 9.4, radius: 2.8, tint: .violet),
        .init(x: 0.75, y: 0.16, vx: -8.3, vy: 6.0, radius: 1.1, tint: .plum),
        .init(x: 0.93, y: 0.26, vx: -5.9, vy: 10.2, radius: 2.1, tint: .pink),
        .init(x: 0.08, y: 0.34, vx: 7.6, vy: -6.4, radius: 1.5, tint: .violet),
        .init(x: 0.24, y: 0.42, vx: 10.4, vy: 5.1, radius: 2.6, tint: .plum),
        .init(x: 0.38, y: 0.31, vx: -6.2, vy: 8.8, radius: 1.0, tint: .violet),
        .init(x: 0.53, y: 0.39, vx: 8.8, vy: -7.1, radius: 1.9, tint: .pink),
        .init(x: 0.69, y: 0.29, vx: -10.1, vy: 5.8, radius: 1.3, tint: .plum),
        .init(x: 0.84, y: 0.45, vx: 6.4, vy: -9.2, radius: 2.5, tint: .violet),
        .init(x: 0.96, y: 0.53, vx: -7.8, vy: 7.0, radius: 0.9, tint: .pink),
        .init(x: 0.11, y: 0.58, vx: 9.5, vy: 6.3, radius: 2.2, tint: .plum),
        .init(x: 0.27, y: 0.68, vx: -7.1, vy: 9.8, radius: 1.4, tint: .pink),
        .init(x: 0.42, y: 0.55, vx: 6.8, vy: -8.0, radius: 2.7, tint: .violet),
        .init(x: 0.59, y: 0.71, vx: -9.7, vy: -5.7, radius: 1.1, tint: .plum),
        .init(x: 0.74, y: 0.62, vx: 8.0, vy: 7.6, radius: 1.8, tint: .pink),
        .init(x: 0.89, y: 0.76, vx: -6.5, vy: 9.1, radius: 2.3, tint: .violet),
        .init(x: 0.06, y: 0.83, vx: 7.3, vy: -8.6, radius: 1.0, tint: .pink),
        .init(x: 0.33, y: 0.88, vx: -8.6, vy: -6.2, radius: 2.0, tint: .plum),
        .init(x: 0.61, y: 0.94, vx: 9.2, vy: -7.4, radius: 1.5, tint: .violet),
        .init(x: 0.86, y: 0.91, vx: -7.5, vy: -9.0, radius: 2.8, tint: .pink),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.008, green: 0.006, blue: 0.018)

                RadialGradient(
                    colors: [
                        Color(red: 0.22, green: 0.08, blue: 0.34).opacity(0.16),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.34, green: 0.06, blue: 0.22).opacity(0.10),
                        .clear,
                    ],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.62
                )

                TimelineView(.animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: reduceMotion || scenePhase != .active
                )) { timeline in
                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        let elapsed = reduceMotion
                            ? 0
                            : timeline.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 600)
                        drawNetwork(in: &context, size: size, elapsed: elapsed)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawNetwork(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval
    ) {
        let positions = particles.map { particle in
            CGPoint(
                x: reflectedPosition(
                    start: particle.x,
                    velocity: particle.vx,
                    elapsed: elapsed,
                    length: size.width
                ),
                y: reflectedPosition(
                    start: particle.y,
                    velocity: particle.vy,
                    elapsed: elapsed,
                    length: size.height
                )
            )
        }
        let connectionDistance = min(160, max(142, size.width * 0.39))

        for firstIndex in positions.indices {
            for secondIndex in positions.index(after: firstIndex)..<positions.endIndex {
                let first = positions[firstIndex]
                let second = positions[secondIndex]
                let distance = hypot(second.x - first.x, second.y - first.y)
                guard distance < connectionDistance else { continue }

                let proximity = 1 - (distance / connectionDistance)
                var path = Path()
                path.move(to: first)
                path.addLine(to: second)
                context.stroke(
                    path,
                    with: .color(Color(red: 0.56, green: 0.32, blue: 0.76)
                        .opacity(0.24 * pow(proximity, 0.9))),
                    lineWidth: 0.5 + (0.55 * proximity)
                )
            }
        }

        for (index, position) in positions.enumerated() {
            let particle = particles[index]
            let color = particle.tint.color
            let radius = particle.radius

            context.fill(
                Path(ellipseIn: CGRect(
                    x: position.x - radius * 4,
                    y: position.y - radius * 4,
                    width: radius * 8,
                    height: radius * 8
                )),
                with: .color(color.opacity(0.06))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: position.x - radius * 2,
                    y: position.y - radius * 2,
                    width: radius * 4,
                    height: radius * 4
                )),
                with: .color(color.opacity(0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: position.x - radius,
                    y: position.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(color.opacity(0.78))
            )
        }
    }

    private func reflectedPosition(
        start: CGFloat,
        velocity: CGFloat,
        elapsed: TimeInterval,
        length: CGFloat
    ) -> CGFloat {
        let padding: CGFloat = 10
        let usableLength = max(length - padding * 2, 1)
        let period = usableLength * 2
        var raw = (start * usableLength + velocity * elapsed)
            .truncatingRemainder(dividingBy: period)
        if raw < 0 { raw += period }
        let reflected = raw <= usableLength ? raw : period - raw
        return padding + reflected
    }
}

private struct NetworkParticle {
    let x: CGFloat
    let y: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let radius: CGFloat
    let tint: NetworkParticleTint
}

private enum NetworkParticleTint {
    case pink
    case violet
    case plum

    var color: Color {
        switch self {
        case .pink:
            return Color(red: 0.88, green: 0.26, blue: 0.62)
        case .violet:
            return Color(red: 0.53, green: 0.34, blue: 0.78)
        case .plum:
            return Color(red: 0.38, green: 0.22, blue: 0.56)
        }
    }
}
