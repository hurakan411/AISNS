import SwiftUI

enum HomeGuideAnchor: Hashable {
    case step(HomeGuideStep)
    case viewport
}

struct HomeGuideAnchorPreference: PreferenceKey {
    static var defaultValue: [HomeGuideAnchor: Anchor<CGRect>] = [:]
    static func reduce(value: inout [HomeGuideAnchor: Anchor<CGRect>], nextValue: () -> [HomeGuideAnchor: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct HomeGuideModalPreference: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    @ViewBuilder
    func homeGuideTarget(_ step: HomeGuideStep?) -> some View {
        if let step {
            self.transformAnchorPreference(key: HomeGuideAnchorPreference.self, value: .bounds) { targets, anchor in
                targets[.step(step)] = anchor
            }
                .id(step)
        } else {
            self
        }
    }

    func homeGuideViewport() -> some View {
        transformAnchorPreference(key: HomeGuideAnchorPreference.self, value: .bounds) { targets, anchor in
            targets[.viewport] = anchor
        }
    }
}

/// Bridges real view anchors to the coordinator. Targets can exist outside the visible viewport;
/// ScrollViewReader reveals them before the bubble becomes tappable.
struct HomeGuideHost: View {
    @ObservedObject var guide: HomeGuideCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let allowed: Bool
    let targets: [HomeGuideStep: CGRect]
    let viewport: CGRect
    let canvas: CGSize
    let japanese: Bool
    let screen: GuideScreen
    @State private var displayedStage: Stage?
    @State private var contentVisible = false
    @State private var displayedIndex = 0
    @State private var displayedCount = 0

    private enum Stage: Equatable {
        case explanation(HomeGuideStep)
        case completion
    }

    private var stage: Stage? {
        guard allowed else { return nil }
        if guide.showsCompletion { return .completion }
        return guide.activeStep.map { .explanation($0) }
    }

    private func advance() {
        guard contentVisible, displayedStage == stage, stage != nil else { return }
        guide.next()
    }

    private struct LaunchContext: Equatable {
        let allowed: Bool
        let available: [HomeGuideStep]
        let revision: Int
        let presenting: Bool
        let screen: GuideScreen
    }

    private var available: [HomeGuideStep] {
        HomeGuideStep.ordered(for: screen).filter { step in
            guard let frame = targets[step] else { return false }
            return !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
                && frame.origin.x.isFinite && frame.origin.y.isFinite
                && frame.width.isFinite && frame.height.isFinite
        }
    }

    var body: some View {
        ZStack {
            if allowed, guide.isPresenting {
                // Keep all underlying controls blocked, including between fading stages.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            Group {
                switch displayedStage {
                case .completion:
                    HomeGuideCompletion(canvas: canvas, japanese: japanese, advance: advance)
                case .explanation(let step):
                    HomeGuideSpotlight(guide: guide, step: step, target: targets[step],
                                       viewport: viewport, canvas: canvas, japanese: japanese,
                                       stepIndex: displayedIndex, stepCount: displayedCount, advance: advance)
                        .id(step)
                case nil:
                    EmptyView()
                }
            }
            .opacity(contentVisible ? 1 : 0)
            .allowsHitTesting(contentVisible && displayedStage == stage)
            .accessibilityHidden(!contentVisible || displayedStage != stage)
        }
        .task(id: stage) {
            let nextStage = stage
            let replacingStage = displayedStage != nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) { contentVisible = false }
            if replacingStage, !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            displayedStage = nextStage
            displayedIndex = guide.index
            displayedCount = guide.steps.count
            guard nextStage != nil else { return }
            // The feed starts scrolling after 80ms and settles in 250ms. Reveal only after
            // the target has arrived, so the bubble does not travel across the screen.
            if case .explanation = nextStage, !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(replacingStage ? 240 : 340)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.12)) { contentVisible = true }
        }
        .task(id: LaunchContext(allowed: allowed, available: available, revision: guide.replayRevision,
                               presenting: guide.isPresenting, screen: screen)) {
            guard allowed else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled else { return }
            guide.presentIfNeeded(screen: screen, available: available)
        }
    }
}

private struct HomeGuideCompletion: View {
    let canvas: CGSize
    let japanese: Bool
    let advance: () -> Void
    @State private var ready = false
    @AccessibilityFocusState private var focused: Bool

    private func dismiss() {
        guard ready else { return }
        advance()
    }

    var body: some View {
        ZStack {
            Color(white: 0.84).opacity(0.30)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(japanese ? "ガイドの再表示" : "Guide replay")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(japanese
                     ? "このガイドは、画面下の一番右にある「設定」の「使い方ガイド」からいつでも見直せます。"
                     : "Replay this guide anytime from How to use UPME in the Settings tab at the bottom right.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(width: min(304, max(1, canvas.width - 40)))
            .background(Theme.aiCardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.lavender.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dismiss() }
            .accessibilityFocused($focused)
            .accessibilityIdentifier("homeGuide.completion")
        }
        .frame(width: canvas.width, height: canvas.height)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }
        .task {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            ready = true
            focused = true
        }
    }
}

private struct HomeGuideSpotlight: View {
    @ObservedObject var guide: HomeGuideCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var explanationFocused: Bool
    let step: HomeGuideStep
    let target: CGRect?
    let viewport: CGRect
    let canvas: CGSize
    let japanese: Bool
    let stepIndex: Int
    let stepCount: Int
    let advance: () -> Void
    @State private var bubbleHeight: CGFloat = 120
    @State private var readyStep: HomeGuideStep?

    private var visibleTarget: CGRect {
        guard let target else { return .null }
        return target.insetBy(dx: -8, dy: -8).intersection(viewport)
    }

    private var targetVisible: Bool {
        let rect = visibleTarget
        guard let target else { return false }
        return !rect.isNull && rect.width >= min(40, target.width)
            && rect.height >= min(40, target.height)
    }

    private var bubbleWidth: CGFloat { min(304, max(1, canvas.width - 40)) }
    private var bubbleBelow: Bool {
        canvas.height - visibleTarget.maxY >= bubbleHeight + 24
            || visibleTarget.minY < bubbleHeight + 24
    }
    private var bubbleY: CGFloat {
        let proposed = bubbleBelow ? visibleTarget.maxY + 18 : visibleTarget.minY - bubbleHeight - 18
        return max(12, min(proposed, canvas.height - bubbleHeight - 12))
    }
    private var hole: CGRect {
        var result = visibleTarget
        // Very tall replies may fill the viewport. Keep the cutout clear of its explanation.
        if result.intersects(CGRect(x: 0, y: bubbleY, width: canvas.width, height: bubbleHeight)) {
            if bubbleBelow { result.size.height = max(0, bubbleY - 12 - result.minY) }
            else {
                let bottom = result.maxY
                result.origin.y = bubbleY + bubbleHeight + 12
                result.size.height = max(0, bottom - result.minY)
            }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Separate hit surface covers even the transparent cutout and bottom navigation.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if targetVisible && readyStep == step { advance() } }
                .accessibilityHidden(true)

            SpotlightMask(hole: targetVisible ? hole : .zero)
                .fill(Color(white: 0.84).opacity(0.30), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            if targetVisible {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.lavender, lineWidth: 2)
                    .frame(width: max(0, hole.width), height: max(0, hole.height))
                    .position(x: hole.midX, y: hole.midY)
                    .allowsHitTesting(false)

                bubble
                    .frame(width: bubbleWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: GuideBubbleHeightPreference.self, value: geometry.size.height)
                        }
                    }
                    .offset(x: (canvas.width - bubbleWidth) / 2, y: bubbleY)
                    .accessibilityIdentifier("homeGuide.bubble")

                GuidePointer()
                    .fill(Theme.aiCardBackground)
                    .frame(width: 22, height: 12)
                    .rotationEffect(.degrees(bubbleBelow ? 0 : 180))
                    .position(x: min(canvas.width - 40, max(40, hole.midX)),
                              y: bubbleBelow ? bubbleY - 5 : bubbleY + bubbleHeight + 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { guide.skip() }
        .onPreferenceChange(GuideBubbleHeightPreference.self) { bubbleHeight = $0 }
        .task(id: step) {
            readyStep = nil
            explanationFocused = false
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 400)) } catch { return }
            guard !Task.isCancelled else { return }
            readyStep = step
            explanationFocused = true
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(step.title(japanese: japanese))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(stepIndex + 1) / \(stepCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize()
            }
            Text(step.detail(japanese: japanese))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.86))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.aiCardBackground)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.lavender.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { if readyStep == step { advance() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if readyStep == step { advance() } }
        .accessibilityFocused($explanationFocused)
    }
}

private struct GuideBubbleHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 120
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SpotlightMask: Shape {
    let hole: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0 && hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14))
        }
        return path
    }
}

private struct GuidePointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
