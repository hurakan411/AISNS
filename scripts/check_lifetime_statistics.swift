// Prepend LifetimeReactionStatistics from AppState.swift and run with swift.
import Foundation

var statistics = LifetimeReactionStatistics()
precondition(statistics.record(id: "old-post", likes: 120, aiReplies: 5))
precondition(!statistics.record(id: "old-post", likes: 120, aiReplies: 5))
precondition(statistics.record(id: "new-post", likes: 40, aiReplies: 2))
// The old post has left the feed; only the new post is supplied on subsequent saves.
precondition(statistics.record(id: "new-post", likes: 80, aiReplies: 4))
precondition(statistics.totalLikes == 200 && statistics.totalAIReplies == 9)

let data = try JSONEncoder().encode(statistics)
var restored = try JSONDecoder().decode(LifetimeReactionStatistics.self, from: data)
precondition(!restored.record(id: "old-post", likes: 120, aiReplies: 5))
precondition(!restored.record(id: "new-post", likes: 0, aiReplies: 0))
precondition(restored.totalLikes == 200 && restored.totalAIReplies == 9)
// Additional AI comments on a reply thread increase the same post's count once.
precondition(restored.record(id: "new-post", likes: 80, aiReplies: 7))
precondition(restored.totalLikes == 200 && restored.totalAIReplies == 12)
precondition(!restored.record(id: "new-post", likes: 80, aiReplies: 7))
precondition(!restored.record(id: "invalid", likes: -1, aiReplies: -5))
print("Lifetime statistics checks passed: pruning, restart, idempotency, delayed replies, monotonic totals")
