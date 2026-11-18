// Combine the Reply declaration from AppState.swift with this script; no network.
import Foundation

let oldData = """
{"id":"12345678-1234-1234-1234-123456789012","authorName":"ゆき","text":"おつかれさま","img":"https://example.test/avatar","isHater":false,"isDefender":false}
""".data(using: .utf8)!
let oldReply = try JSONDecoder().decode(Reply.self, from: oldData)
precondition(oldReply.characterId == nil)
precondition(oldReply.canReceiveUserReply)
let reply = Reply(authorName: "ゆき", text: "おつかれさま🙌", img: "https://example.test/avatar",
                  isHater: false, isDefender: false, characterId: "v1-03")
let saved = try JSONEncoder().encode(reply)
let decoded = try JSONDecoder().decode(Reply.self, from: saved)
precondition(decoded == reply)
precondition(decoded.characterId == "v1-03")
// Old decoders can ignore the additive key; the old fields remain intact.
let json = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
precondition(json["authorName"] as? String == "ゆき")
precondition(json["text"] as? String == "おつかれさま🙌")
print("Reply character checks passed: legacy decoding and character ID round-trip")
