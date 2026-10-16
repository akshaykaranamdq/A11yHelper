import SwiftUI
import Observation

/// What Home shows for each reported issue.
struct ReportedIssue: Identifiable {
    let id = UUID()
    var checkpoint: String
    var summary: String
    var screenshots: [UIImage] = []
    var createdAt: Date
}

/// In-memory list of reported issues. Swap the storage for the real API (or local persistence) later;
/// Home only talks to this type.
@MainActor @Observable
final class IssueStore {
    private(set) var issues: [ReportedIssue]

    init(seedSamples: Bool = IssueOptionsEnvironment.useSampleData) {
        issues = seedSamples ? Self.samples : []
    }

    func add(_ draft: IssueDraft) {
        let issue = ReportedIssue(checkpoint: draft.checkpoint.title,
                                  summary: draft.issueDescription,
                                  screenshots: draft.screenshots,
                                  createdAt: .now)
        issues.insert(issue, at: 0)
    }

    private static var samples: [ReportedIssue] {
        let now = Date.now
        return [
            ReportedIssue(checkpoint: "Touch target size",
                          summary: "Target smaller than 44 × 44 pt on the close button",
                          createdAt: now.addingTimeInterval(-12 * 60)),
            ReportedIssue(checkpoint: "Labels and names",
                          summary: "Icon-only button has no accessibility label",
                          createdAt: now.addingTimeInterval(-3 * 3600)),
            ReportedIssue(checkpoint: "Color contrast",
                          summary: "Secondary text contrast is below 4.5:1 on the settings screen",
                          createdAt: now.addingTimeInterval(-26 * 3600)),
            ReportedIssue(checkpoint: "Focus order",
                          summary: "VoiceOver reads the footer before the main content",
                          createdAt: now.addingTimeInterval(-3 * 86_400))
        ]
    }
}
