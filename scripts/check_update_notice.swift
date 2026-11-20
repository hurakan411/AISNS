// Prepend UpdateNoticeEligibility from ContentView.swift and run with swift.
import Foundation

let suite = "upme-update-notice-checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let version = "1.1.4"

// A new install remains excluded after creating an ID and completing onboarding.
precondition(!UpdateNoticeEligibility.prepare(version: version, installedVersion: version, defaults: defaults))
defaults.set("new-user", forKey: "userId")
defaults.set(true, forKey: "hasCompletedOnboarding")
precondition(!UpdateNoticeEligibility.prepare(version: version, installedVersion: version, defaults: defaults))

defaults.removePersistentDomain(forName: suite)
// Existing users remain eligible until the view records the displayed version.
defaults.set("existing-user", forKey: "userId")
defaults.set("1.1.3", forKey: "lastSeenUpdateNoticeVersion")
precondition(defaults.string(forKey: "lastSeenUpdateNoticeVersion") != version)
precondition(UpdateNoticeEligibility.prepare(version: version, installedVersion: version, defaults: defaults))
precondition(UpdateNoticeEligibility.prepare(version: version, installedVersion: version, defaults: defaults))
defaults.set(version, forKey: "lastSeenUpdateNoticeVersion")
precondition(defaults.string(forKey: "lastSeenUpdateNoticeVersion") == version)

defaults.removePersistentDomain(forName: suite)
// A different app version must not create an eligibility decision for this notice.
defaults.set("existing-user", forKey: "userId")
precondition(!UpdateNoticeEligibility.prepare(version: version, installedVersion: "1.1.3", defaults: defaults))
precondition(defaults.object(forKey: "updateNoticeEligible.\(version)") == nil)
precondition(UpdateNoticeEligibility.prepare(version: version, installedVersion: version, defaults: defaults))
print("Update notice checks passed: fresh install, relaunch, existing user, version gating")
