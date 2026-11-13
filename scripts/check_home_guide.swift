import Foundation

@main
struct HomeGuideChecks {
    @MainActor
    static func main() {
        let suite = "test.upme.home-guide.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            count += 1
        }
        func store(_ key: String, persists: Bool = true) -> HomeGuideProgressStore {
            HomeGuideProgressStore(defaults: defaults, key: key, persists: persists)
        }
        func finish(_ guide: HomeGuideCoordinator) {
            while guide.activeStep != nil { guide.next() }
            if guide.showsCompletion { guide.next() }
        }

        let home = HomeGuideStep.ordered(for: .home)
        let allScreens = GuideScreen.allCases
        check(home == [.compose, .reactions, .buzz, .aiReply, .reply, .regular], "Home explains viral posts after reactions")
        check(allScreens.count == 4, "Each main screen has a guide")
        check(allScreens.allSatisfy { !HomeGuideStep.ordered(for: $0).isEmpty }, "Every screen has guide steps")
        check(home.map { $0.title(japanese: true) } == ["投稿", "リアクション", "バズ", "AIの返信", "AIとの会話", "常連AI"], "Japanese home headings are concise")
        check(home.map { $0.title(japanese: false) } == ["Posts", "Reactions", "Going viral", "AI replies", "Conversations", "Regular AIs"], "English home headings are concise")

        let first = HomeGuideCoordinator(store: store("first"))
        first.presentIfNeeded(screen: .home, available: home)
        check(first.activeStep == .compose && first.screen == .home, "Home starts at compose")
        first.next()
        check(first.activeStep == .reactions, "Home advances in order")
        let relaunched = HomeGuideCoordinator(store: store("first"))
        relaunched.presentIfNeeded(screen: .home, available: home)
        check(relaunched.activeStep == .reactions, "Unfinished home guide resumes")
        while relaunched.activeStep != nil { relaunched.next() }
        check(relaunched.showsCompletion, "Home ends with replay reminder")
        finish(relaunched)
        relaunched.next()
        let completedHome = HomeGuideCoordinator(store: store("first"))
        completedHome.presentIfNeeded(screen: .home, available: home)
        check(!completedHome.isPresenting, "Completed home guide stays complete")
        completedHome.requestReplay(for: .home)
        completedHome.presentIfNeeded(screen: .home, available: home)
        check(completedHome.activeStep == .compose, "Home can be replayed")

        let multi = store("multi")
        let stats = HomeGuideCoordinator(store: multi)
        let statsSteps = HomeGuideStep.ordered(for: .stats)
        stats.presentIfNeeded(screen: .stats, available: statsSteps)
        check(stats.activeStep == .statsRank && stats.steps == statsSteps, "Statistics has its own ordered guide")
        stats.skip()
        let statsAgain = HomeGuideCoordinator(store: multi)
        statsAgain.presentIfNeeded(screen: .stats, available: statsSteps)
        check(!statsAgain.isPresenting, "Skipping a screen suppresses its automatic guide")
        statsAgain.requestReplay(for: .stats)
        statsAgain.presentIfNeeded(screen: .stats, available: statsSteps)
        check(statsAgain.activeStep == .statsRank, "Skipped statistics guide can be replayed")
        let profile = HomeGuideCoordinator(store: multi)
        let profileSteps = HomeGuideStep.ordered(for: .profile)
        profile.presentIfNeeded(screen: .profile, available: profileSteps)
        check(profile.activeStep == .profileAvatar, "Profile guide remains independent after statistics is skipped")
        let post = HomeGuideCoordinator(store: multi)
        post.presentIfNeeded(screen: .post, available: HomeGuideStep.ordered(for: .post))
        check(post.activeStep == .postEditor, "Post guide starts at the editor")

        let deferred = HomeGuideCoordinator(store: store("deferred"))
        deferred.presentIfNeeded(screen: .home, available: [.compose])
        check(deferred.activeStep == .compose, "Only available home targets are shown")
        finish(deferred)
        let deferredReply = HomeGuideCoordinator(store: store("deferred"))
        deferredReply.presentIfNeeded(screen: .home, available: home)
        check(deferredReply.steps == [.reactions, .buzz, .aiReply, .reply, .regular], "Previously unavailable home targets remain pending")
        let emptyPost = HomeGuideCoordinator(store: store("empty-post"))
        emptyPost.presentIfNeeded(screen: .post, available: [])
        check(!emptyPost.isPresenting, "No guide appears without a visible target")

        let manual = HomeGuideCoordinator(store: store("manual", persists: false), automaticEnabled: false)
        manual.presentIfNeeded(screen: .profile, available: profileSteps)
        check(!manual.isPresenting, "Preview guide stays closed until requested")
        manual.requestReplay(for: .profile)
        manual.presentIfNeeded(screen: .profile, available: profileSteps)
        check(manual.activeStep == .profileAvatar, "Manual profile replay starts at its first step")
        finish(manual)
        check(defaults.data(forKey: "manual") == nil, "Non-persistent preview never writes progress")

        let legacyKey = "legacy"
        defaults.set(Data(#"{"acknowledged":["compose"],"skipped":true}"#.utf8), forKey: legacyKey)
        let legacy = store(legacyKey)
        check(legacy.pending(for: .post, in: HomeGuideStep.ordered(for: .post)).isEmpty, "Older global Skip preference remains honored")
        check(profileSteps == [.profileAvatar, .profileIdentity, .profileRegulars],
              "Profile explains only its own elements")
        let oldProfile = "old-profile"
        defaults.set(Data(#"{"acknowledged":["profileAvatar","profileIdentity","profileRank","profileRegulars","profileSettings","profileHaters","profileAds","profileContact","profileLegal","profileGuide"]}"#.utf8), forKey: oldProfile)
        check(store(oldProfile).pending(for: .profile, in: profileSteps).isEmpty,
              "Legacy settings acknowledgements remain readable without obsolete steps")
        let gearProfile = "gear-profile"
        defaults.set(Data(#"{"acknowledged":["profileAvatar","profileIdentity","profileRank","profileRegulars","profileSettingsEntry"]}"#.utf8), forKey: gearProfile)
        check(store(gearProfile).pending(for: .profile, in: profileSteps).isEmpty,
              "Progress from the previous gear-entry tour remains complete")
        let oldHome = "old-home"
        defaults.set(Data(#"{"acknowledged":["compose","reactions","aiReply","reply","regular"]}"#.utf8), forKey: oldHome)
        check(store(oldHome).pending(for: .home, in: home) == [.buzz],
              "Existing users receive just the newly added viral explanation")
        check(!GuideScreen.allCases.map(\.rawValue).contains("settings"), "Settings has no automatic or replayable guide")
        check(HomeGuideStep.buzz.detail(japanese: true).contains("5倍") && HomeGuideStep.buzz.detail(japanese: false).contains("5×"),
              "Viral multipliers are explained in both languages")
        check(HomeGuideStep.buzz.detail(japanese: true).contains("3倍") && HomeGuideStep.buzz.detail(japanese: false).contains("3×"),
              "Follower gains use the three-times multiplier")
        check(HomeGuideStep.buzz.detail(japanese: true).contains("24時間") && HomeGuideStep.buzz.detail(japanese: false).contains("24 hours"),
              "Both languages explain the 24-hour cooldown")
        print("PASS: \(count) multi-screen guide checks")
    }
}
