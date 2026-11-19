// Prepend the pure types above @MainActor in DailyReminder.swift, then run with swift.
import Foundation
import CryptoKit

let copyURL = URL(fileURLWithPath: "AppCode/DailyReminderCopy.json")
let copy = try JSONDecoder().decode([String: [String: [String]]].self, from: Data(contentsOf: copyURL))
precondition(copy.count == 30)
for slot in 1...30 {
    let id = String(format: "v1-%02d", slot)
    for language in ["ja", "en"] {
        let messages = copy[id]![language]!
        precondition(messages.count == 10 && Set(messages).count == 10)
        precondition(messages.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 100 })
    }
}

let planner = DailyReminderPlanner(copy: copy)
let calendar = DailyReminderPlanner.calendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
let now = date("2026-11-19T10:00:00+09:00")
let regulars = [ReminderRegular(id: "yuki", name: "ゆき", characterID: "v1-01"),
                ReminderRegular(id: "ren", name: "れん", characterID: "v1-03")]
func plan(at time: Date = now, anchor: Date = now, posted: Date? = nil, people: [ReminderRegular] = regulars,
          language: String = "ja", history: [PlannedReminder] = [], limit: Int = 60) -> [PlannedReminder] {
    planner.plan(now: time, cadenceAnchor: anchor, lastPost: posted, regulars: people, language: language,
                 history: history, seed: "fixed-test-seed", calendar: calendar, limit: limit)
}

let entries = plan()
precondition(entries.count == 60 && Set(entries.map(\.identifier)).count == 60)
precondition(entries.first!.date == date("2026-11-21T20:00:00+09:00"))
for (a, b) in zip(entries, entries.dropFirst()) {
    precondition(calendar.dateComponents([.day], from: a.date, to: b.date).day == 2)
    precondition(a.senderID != b.senderID)
}
// The same two-day cadence continues regardless of inactivity.
precondition(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: entries[40].date)).day == 82)
precondition(entries.allSatisfy { calendar.component(.hour, from: $0.date) == 20 && calendar.component(.minute, from: $0.date) == 0 })
precondition(plan(posted: now).first!.dayID == "2026-11-21")
let dueMorning = date("2026-11-21T09:00:00+09:00")
precondition(plan(at: dueMorning).first!.dayID == "2026-11-21")
precondition(plan(at: dueMorning, posted: dueMorning).first!.dayID == "2026-11-23")
precondition(plan(at: date("2026-11-21T20:00:00+09:00")).first!.dayID == "2026-11-23")
precondition(plan(at: date("2026-11-21T23:59:00+09:00")).first!.dayID == "2026-11-23")
precondition(plan(limit: 0).isEmpty && plan(limit: 5).count == 5)
precondition(plan(people: []).allSatisfy { $0.title == "UPME!" && $0.characterID == "upme" })
precondition(entries.allSatisfy { $0.title == "UPME!｜ゆき" || $0.title == "UPME!｜れん" })

let solo = plan(people: [regulars[0]])
for start in 0...(solo.count - 10) {
    precondition(Set(solo[start..<(start + 10)].map(\.messageIndex)).count == 10)
}
let tomorrow = plan(at: date("2026-11-22T09:00:00+09:00"), people: [regulars[0]], history: solo)
precondition(tomorrow.first!.body == solo[1].body) // Refreshing the queue preserves the next choice.
let english = plan(language: "en")
precondition(english.allSatisfy { copy[$0.characterID]!["en"]!.contains($0.body) })
precondition(plan() == entries) // Deterministic per install/day across restarts.
precondition(ReminderRegular.characterID("v1-17", regularID: "yuki") == "v1-17")
precondition(ReminderRegular.characterID(nil, regularID: "yuki") == ReminderRegular.characterID("unknown", regularID: "yuki"))

// Local 20:00 remains 20:00 through daylight-saving transitions.
let newYork = DailyReminderPlanner.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
let dst = planner.plan(now: date("2027-03-12T12:00:00-05:00"), cadenceAnchor: date("2027-03-10T12:00:00-05:00"), lastPost: nil, regulars: regulars,
    language: "en", history: [], seed: "dst", calendar: newYork, limit: 5)
precondition(dst.allSatisfy { newYork.component(.hour, from: $0.date) == 20 })
precondition(zip(dst, dst.dropFirst()).contains { $1.date.timeIntervalSince($0.date) == 47 * 3600 })
print("Reminder checks passed: 600 messages, 20:00, fixed two-day cadence, post suppression, rotation, restart, English, DST")
