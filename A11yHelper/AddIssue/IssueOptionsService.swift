import Foundation
import UIKit

// MARK: - Contract

/// Source of the options shown on the New issue screen.
protocol IssueOptionsService: Sendable {
    func fetchCheckpoints() async throws -> [IssueOption]
    func fetchDescriptions(checkpointID: String) async throws -> [IssueOption]
    func fetchTechniques(checkpointID: String) async throws -> [String]
    func submit(_ draft: IssueDraft) async throws
}

enum IssueOptionsError: Error {
    case badStatus(Int)
}

// MARK: - URLSession implementation

/// TODO: confirm base URL, paths, auth headers and response shape with the real API.
/// Everything API-specific lives in this file (paths + `OptionDTO`).
struct APIIssueOptionsService: IssueOptionsService {
    /// Used by `AddIssueView()` when no service is injected.
    /// TODO: replace with the real base URL (and auth headers).
    static let live = APIIssueOptionsService(baseURL: URL(string: "https://api.example.com")!)

    var baseURL: URL
    var headers: [String: String] = [:]          // e.g. ["Authorization": "Bearer …"]
    var session: URLSession = .shared

    /// TODO: confirm the real submit endpoint and body (JSON vs multipart for screenshots).
    func submit(_ draft: IssueDraft) async throws {
        struct Body: Encodable {
            let checkpointID, descriptionID, issueDescription, technique, recommendation: String
            let screenshots: [String]       // base64 JPEG
        }
        let body = Body(
            checkpointID: draft.checkpoint.id,
            descriptionID: draft.description.id,
            issueDescription: draft.issueDescription,
            technique: draft.technique,
            recommendation: draft.recommendation,
            screenshots: draft.screenshots.compactMap { $0.jpegData(compressionQuality: 0.8)?.base64EncodedString() }
        )
        var request = URLRequest(url: baseURL.appending(path: "issues"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IssueOptionsError.badStatus(http.statusCode)
        }
    }

    func fetchCheckpoints() async throws -> [IssueOption] {
        try await get("checkpoints", as: [OptionDTO].self).map(\.option)
    }

    func fetchDescriptions(checkpointID: String) async throws -> [IssueOption] {
        try await get("checkpoints/\(checkpointID)/descriptions", as: [OptionDTO].self).map(\.option)
    }

    func fetchTechniques(checkpointID: String) async throws -> [String] {
        try await get("checkpoints/\(checkpointID)/techniques", as: [OptionDTO].self).map(\.title)
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IssueOptionsError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Placeholder shape: { "id": "…" | 123, "title": "…" }. Adjust once the real JSON is known.
private struct OptionDTO: Decodable {
    let id: String
    let title: String

    var option: IssueOption { IssueOption(title, id: id) }

    private enum CodingKeys: String, CodingKey { case id, title }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
    }
}

// MARK: - Mock (previews and tests)

/// Chooses where the New issue screen gets its options.
/// Flip `useSampleData` to `false` once the real API is ready.
enum IssueOptionsEnvironment {
    static let useSampleData = true

    static var service: any IssueOptionsService {
        useSampleData ? MockIssueOptionsService() : APIIssueOptionsService.live
    }
}

/// Sample data for previews, demos and tests. Descriptions and techniques depend on the checkpoint,
/// mirroring how the real API is expected to behave.
struct MockIssueOptionsService: IssueOptionsService {
    var delay: Duration = .milliseconds(500)
    var shouldFail = false

    private struct Entry {
        let checkpoint: IssueOption
        let descriptions: [String]
        let techniques: [String]
    }

    private static let entries: [Entry] = [
        Entry(checkpoint: IssueOption("Labels and names", id: "labels"),
              descriptions: ["Button has no accessibility label",
                             "Label doesn't describe the action",
                             "Visible text and spoken label don't match",
                             "Decorative element is announced"],
              techniques: ["accessibilityLabel", "accessibilityHidden", "accessibilityInputLabels"]),

        Entry(checkpoint: IssueOption("Touch target size", id: "targets"),
              descriptions: ["Target smaller than 44 × 44 pt",
                             "Targets too close together",
                             "Tappable area smaller than the visible control"],
              techniques: ["frame(minWidth:minHeight:)", "contentShape", "padding"]),

        Entry(checkpoint: IssueOption("Color contrast", id: "contrast"),
              descriptions: ["Text contrast below 4.5:1",
                             "Icon or border contrast below 3:1",
                             "Information conveyed by color alone",
                             "Disabled state unreadable"],
              techniques: ["Use semantic colors", "Increase text weight", "Add a non-color indicator"]),

        Entry(checkpoint: IssueOption("Focus order", id: "focus"),
              descriptions: ["VoiceOver order doesn't match visual order",
                             "Focus is lost after an action",
                             "Element can't be reached with VoiceOver"],
              techniques: ["accessibilitySortPriority", "accessibilityElement(children:)", "AccessibilityFocusState"]),

        Entry(checkpoint: IssueOption("Dynamic Type", id: "dynamictype"),
              descriptions: ["Text doesn't scale with system size",
                             "Text is truncated at larger sizes",
                             "Layout breaks at accessibility sizes"],
              techniques: ["Use Dynamic Type text styles", "ScaledMetric", "ViewThatFits"]),

        Entry(checkpoint: IssueOption("Headings and structure", id: "headings"),
              descriptions: ["Section title isn't marked as a heading",
                             "Heading levels are skipped",
                             "Related items aren't grouped"],
              techniques: ["accessibilityAddTraits(.isHeader)", "accessibilityElement(children: .combine)", "accessibilityHeading"]),

        Entry(checkpoint: IssueOption("Forms and inputs", id: "forms"),
              descriptions: ["Field has no label",
                             "Error isn't announced",
                             "Required state isn't conveyed",
                             "Wrong keyboard type"],
              techniques: ["accessibilityLabel", "AccessibilityNotification.Announcement", "keyboardType", "textContentType"]),

        Entry(checkpoint: IssueOption("Images and icons", id: "images"),
              descriptions: ["Informative image has no description",
                             "Icon-only button has no label",
                             "Image of text used instead of real text"],
              techniques: ["accessibilityLabel", "accessibilityHidden", "Label with icon and title"]),

        Entry(checkpoint: IssueOption("Gestures and motion", id: "gestures"),
              descriptions: ["Action only available through a gesture",
                             "Animation can't be reduced",
                             "Timeout with no way to extend"],
              techniques: ["accessibilityAction", "accessibilityReduceMotion", "Provide a button alternative"]),

        Entry(checkpoint: IssueOption("Status and announcements", id: "status"),
              descriptions: ["Loading state isn't announced",
                             "Success or error message isn't announced",
                             "Toast disappears before it can be read"],
              techniques: ["AccessibilityNotification.Announcement", "accessibilityLiveRegion", "UIAccessibility.post"])
    ]

    func fetchCheckpoints() async throws -> [IssueOption] {
        try await simulate()
        return Self.entries.map(\.checkpoint)
    }

    func fetchDescriptions(checkpointID: String) async throws -> [IssueOption] {
        try await simulate()
        return Self.entries.first { $0.checkpoint.id == checkpointID }?
            .descriptions.map { IssueOption($0) } ?? []
    }

    func fetchTechniques(checkpointID: String) async throws -> [String] {
        try await simulate()
        return Self.entries.first { $0.checkpoint.id == checkpointID }?.techniques ?? []
    }

    func submit(_ draft: IssueDraft) async throws {
        try await simulate()
    }

    private func simulate() async throws {
        try await Task.sleep(for: delay)
        if shouldFail { throw URLError(.notConnectedToInternet) }
    }
}
