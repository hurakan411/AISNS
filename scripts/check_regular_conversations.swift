// Combine the RegularConversation / RegularFollower declarations from AppState.swift
// with this script and run with `xcrun swift -`. No app data or network access.
import Foundation

let legacy = """
{"id":"test","authorName":"ゆき","avatarURL":"","memories":[],"recentInteractions":["old-1","old-2","old-3"],"createdAt":0}
""".data(using: .utf8)!
var follower = try JSONDecoder().decode(RegularFollower.self, from: legacy)
precondition(follower.conversationTexts == nil)
precondition(follower.impressionUpdatedAt == nil)
let profileDate = Date(timeIntervalSince1970: 1_700_000_100)
let overview = String(repeating: "自然な総評。", count: 30)
follower.storeImpression("Detailed profile", summary: overview, language: "ja", receivedAt: profileDate)
precondition(follower.impressionSummary == overview)
precondition(follower.impressionUpdatedAt == profileDate)
for empty in [nil, "", " \n "] as [String?] {
    follower.storeImpression(empty, summary: "must not replace", language: "en", receivedAt: profileDate.addingTimeInterval(100))
    precondition(follower.impressionUpdatedAt == profileDate)
    precondition(follower.impression == "Detailed profile")
    precondition(follower.impressionSummary == overview)
}
let savedProfile = try JSONDecoder().decode(RegularFollower.self, from: JSONEncoder().encode(follower))
precondition(savedProfile.impressionUpdatedAt == profileDate)
let legacyConversation = """
{"userText":"original","replyText":"reply","isUserReply":false}
""".data(using: .utf8)!
let decodedLegacyConversation = try JSONDecoder().decode(RegularConversation.self, from: legacyConversation)
precondition(decodedLegacyConversation.occurredAt == nil)
precondition(!follower.canShowImpression)
let firstPost = UUID()
follower.recordImpressionPost(firstPost)
follower.recordImpressionPost(firstPost)
precondition(follower.impressionPostIDs?.count == 1)
precondition(!follower.canShowImpression)
follower.recordImpressionPost(UUID())
precondition(!follower.canShowImpression)
follower.recordImpressionPost(UUID())
precondition(follower.canShowImpression)
follower.recordImpressionPost(UUID())
precondition(follower.impressionPostIDs?.count == 3)
for i in 0..<12 {
    let original = RegularConversation(userText: "Original post \(i)\nそのまま🌸", replyText: "Exact reply \(i)！", isUserReply: i.isMultiple(of: 2),
                                       occurredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)))
    follower.rememberConversation(summary: "summary-\(i)", original: original)
    precondition(follower.recentInteractions.count <= 10)
    precondition(follower.conversationTexts?.count == follower.recentInteractions.count)
    if i == 0 {
        precondition(follower.conversationTexts![0] == nil)
        precondition(follower.conversationTexts![3] == original)
    }
}
precondition(follower.recentInteractions.first == "summary-2")
precondition(follower.conversationTexts!.first!?.userText == "Original post 2\nそのまま🌸")
let decoded = try JSONDecoder().decode(RegularFollower.self, from: JSONEncoder().encode(follower))
precondition(decoded == follower)
precondition(decoded.conversationTexts!.last!?.occurredAt == Date(timeIntervalSince1970: 1_700_000_011))
follower.rememberConversation(summary: "missing-original", original: nil)
precondition(follower.conversationTexts!.last! == nil)
precondition(follower.recentInteractions.last == "missing-original")
print("Regular conversation checks passed: legacy decoding, alignment, rolling limit, exact text, persistence, missing originals")
