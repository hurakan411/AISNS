// Prepend AIReplyBackgroundLease from AppState.swift and run with `xcrun swift -`.
import Foundation

struct UIBackgroundTaskIdentifier: Hashable {
    let value: Int
    static let invalid = Self(value: -1)
}

final class UIApplication {
    static let shared = UIApplication()
    var nextID = 0
    var reject = false
    var handlers: [UIBackgroundTaskIdentifier: () -> Void] = [:]
    var ended: [UIBackgroundTaskIdentifier] = []

    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        precondition(Thread.isMainThread)
        if reject { return .invalid }
        nextID += 1
        let id = UIBackgroundTaskIdentifier(value: nextID)
        handlers[id] = expirationHandler
        return id
    }

    func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {
        precondition(Thread.isMainThread)
        precondition(!ended.contains(id), "Lease ended twice")
        ended.append(id)
        handlers[id] = nil
    }
}

func drainMainQueue() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

private let app = UIApplication.shared
private let request = URLRequest(url: URL(string: "https://example.invalid")!)
private let firstTask = URLSession.shared.dataTask(with: request)
private let first = AIReplyBackgroundLease()
first.start(task: firstTask)
private let secondTask = URLSession.shared.dataTask(with: request)
private let second = AIReplyBackgroundLease()
second.start(task: secondTask)
precondition(app.handlers.count == 2)

// Expiry cancels just its own request, and a later completion cannot end it twice.
app.handlers[UIBackgroundTaskIdentifier(value: 1)]!()
precondition(firstTask.state == .canceling || firstTask.state == .completed)
precondition(secondTask.state == .suspended)
first.finish()
drainMainQueue()
precondition(app.ended.count == 1 && app.handlers.count == 1)

// Completion must release after the queued model/save work, never before it.
private var savedBeforeEnd = false
DispatchQueue.main.async { savedBeforeEnd = app.ended.count == 1 }
second.finish()
drainMainQueue()
precondition(savedBeforeEnd && app.ended.count == 2 && app.handlers.isEmpty)

// iOS may refuse background time; this must remain safe.
app.reject = true
private let rejected = AIReplyBackgroundLease()
rejected.start(task: secondTask)
rejected.finish()
drainMainQueue()
precondition(app.ended.count == 2)
print("AI reply background lease checks passed")
