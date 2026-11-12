import Foundation

struct UserProgress: Codable, Equatable {
    var followers = 0
    var totalPosts = 0
    var hasCompletedOnboarding = false
}

/// Keeps startup independent of the network. All state changes and callbacks run on the main queue.
final class UserProgressSync {
    private struct Cache: Codable {
        var progress: UserProgress
        var needsSync: Bool
    }

    private(set) var progress: UserProgress
    var onProgressChange: ((UserProgress) -> Void)?

    private let usersURL: URL
    private let userURL: URL
    private let userID: String
    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheKey: String
    private var needsSync: Bool
    private var registered = false
    private(set) var hasReadServer = false
    private var requestInFlight = false
    private var reading = false
    private var postsBeforeFirstRead = 0
    private var postsDuringRead = 0
    private var followersBeforeFirstRead = 0
    private var followersDuringRead = 0
    private var revision = 0

    init(baseURL: URL, userID: String, onboardingCompleted: Bool,
         session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.userID = userID
        self.session = session
        self.defaults = defaults
        usersURL = baseURL.appendingPathComponent("api/users")
        userURL = usersURL.appendingPathComponent(userID)
        // Debug and production can use the same local UUID, but have different databases.
        cacheKey = "userProgress.v1.\(baseURL.absoluteString).\(userID)"
        let cached = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        var restored = cached?.progress ?? UserProgress()
        restored.followers = max(0, restored.followers)
        restored.totalPosts = max(0, restored.totalPosts)
        restored.hasCompletedOnboarding = restored.hasCompletedOnboarding || onboardingCompleted
        progress = restored
        needsSync = (cached?.needsSync ?? false) || (onboardingCompleted && cached?.progress.hasCompletedOnboarding != true)
    }

    func updateLocal(followers: Int, totalPosts: Int, onboardingCompleted: Bool) {
        let next = UserProgress(followers: max(0, followers), totalPosts: max(0, totalPosts),
                                hasCompletedOnboarding: progress.hasCompletedOnboarding || onboardingCompleted)
        guard next != progress else { return }
        let addedPosts = max(0, next.totalPosts - progress.totalPosts)
        let addedFollowers = max(0, next.followers - progress.followers)
        if !hasReadServer {
            postsBeforeFirstRead += addedPosts
            followersBeforeFirstRead += addedFollowers
        } else if reading {
            postsDuringRead += addedPosts
            followersDuringRead += addedFollowers
        }
        progress = next
        revision += 1
        needsSync = true
        persist()
    }

    /// Repairs an interrupted reward write from the post ledger. This is an absolute
    /// total already earned, not a new delta to add to the server's first read.
    func recoverFollowerTotal(atLeast total: Int) {
        guard total > progress.followers else { return }
        progress.followers = total
        revision += 1
        needsSync = true
        persist()
    }

    func refresh() {
        guard !requestInFlight else { return }
        if registered && hasReadServer && needsSync {
            sync()
            return
        }
        requestInFlight = true
        reading = true
        postsDuringRead = 0
        followersDuringRead = 0
        if registered {
            readProgress()
            return
        }
        send(url: usersURL, method: "POST", body: ["user_id": userID]) { [weak self] json in
            guard let self else { return }
            guard let json, let completed = Self.bool(json["has_completed_onboarding"]) else {
                self.finishFailedRead()
                return
            }
            self.registered = true
            let previous = self.progress
            self.progress.hasCompletedOnboarding = self.progress.hasCompletedOnboarding || completed
            self.needsSync = self.needsSync || (self.progress.hasCompletedOnboarding && !completed)
            self.persist()
            if self.progress != previous { self.onProgressChange?(self.progress) }
            self.readProgress()
        }
    }

    /// Coalesces updates and never sends PUT before registration and the initial read finish.
    func sync() {
        needsSync = true
        persist()
        guard !requestInFlight else { return }
        guard registered && hasReadServer else {
            refresh()
            return
        }
        requestInFlight = true
        let sentRevision = revision
        let snapshot = progress
        send(url: userURL, method: "PUT", body: [
            "total_followers": snapshot.followers,
            "total_posts": snapshot.totalPosts,
            "has_completed_onboarding": snapshot.hasCompletedOnboarding
        ]) { [weak self] json in
            guard let self else { return }
            self.requestInFlight = false
            guard json?["status"] as? String == "success" else { return }
            self.needsSync = self.revision != sentRevision
            self.persist()
            if self.needsSync { self.sync() }
        }
    }

    private func readProgress() {
        send(url: userURL, method: "GET") { [weak self] json in
            guard let self else { return }
            guard let json, let followers = json["total_followers"] as? Int, followers >= 0,
                  let posts = json["total_posts"] as? Int, posts >= 0,
                  let completed = Self.bool(json["has_completed_onboarding"]) else {
                self.finishFailedRead()
                return
            }
            let addedPosts = self.hasReadServer ? self.postsDuringRead : self.postsBeforeFirstRead
            let addedFollowers = self.hasReadServer ? self.followersDuringRead : self.followersBeforeFirstRead
            let remote = UserProgress(followers: followers, totalPosts: posts, hasCompletedOnboarding: completed)
            // A read started before a local post must not erase that post or its earned followers.
            self.progress.followers = max(self.progress.followers, followers + addedFollowers)
            self.progress.totalPosts = max(self.progress.totalPosts, posts + addedPosts)
            self.progress.hasCompletedOnboarding = self.progress.hasCompletedOnboarding || completed
            self.hasReadServer = true
            self.postsBeforeFirstRead = 0
            self.followersBeforeFirstRead = 0
            self.reading = false
            self.requestInFlight = false
            self.needsSync = self.needsSync || self.progress != remote
            self.persist()
            self.onProgressChange?(self.progress)
            if self.needsSync { self.sync() }
        }
    }

    private func finishFailedRead() {
        reading = false
        requestInFlight = false
        // Keep cached state and pending writes. A foreground transition or next sync retries.
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Cache(progress: progress, needsSync: needsSync)) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private func send(url: URL, method: String, body: [String: Any]? = nil,
                      completion: @escaping ([String: Any]?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json: [String: Any]?
            if error == nil, (200..<300).contains(status), let data {
                json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            } else { json = nil }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as Int: return value != 0
        case let value as String:
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }
}
