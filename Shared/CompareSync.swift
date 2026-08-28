import AppKit
import Foundation

enum CompareSync {
    static let sessionBegan = Notification.Name("com.cadence.compare.sessionBegan")
    static let sessionEnded = Notification.Name("com.cadence.compare.sessionEnded")
    static let cadenceTranscript = Notification.Name("com.cadence.dictation.transcriptReady")
    static let transcriptKey = "text"
    static let cadenceBundleID = "com.cadence.dictation"
    static let compareBundleID = "com.cadence.compare"

    static func postBegan() {
        DistributedNotificationCenter.default().postNotificationName(
            sessionBegan,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postEnded() {
        DistributedNotificationCenter.default().postNotificationName(
            sessionEnded,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postCadenceTranscript(_ text: String) {
        DistributedNotificationCenter.default().postNotificationName(
            cadenceTranscript,
            object: nil,
            userInfo: [transcriptKey: text],
            deliverImmediately: true
        )
    }

    static func cadenceIsRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: cadenceBundleID).isEmpty == false
    }

    static func compareIsRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: compareBundleID).isEmpty == false
    }
}
