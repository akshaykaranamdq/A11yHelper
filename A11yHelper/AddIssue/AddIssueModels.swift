import SwiftUI
import Observation

// MARK: - Models

struct IssueOption: Identifiable, Hashable {
    let id: String
    let title: String
    init(_ title: String, id: String? = nil) {
        self.title = title
        self.id = id ?? title
    }
}

enum IssueField: Hashable, CaseIterable {
    case checkpoint, description, issueDescription, technique, recommendation, screenshots
}

/// A screenshot keeps its original so annotations stay editable.
struct Screenshot: Identifiable {
    let id = UUID()
    let original: UIImage
    var annotations: [Annotation] = []
    private(set) var rendered: UIImage

    init(image: UIImage) {
        original = image
        rendered = image
    }

    mutating func apply(_ annotations: [Annotation]) {
        self.annotations = annotations
        rendered = annotations.isEmpty
            ? original
            : AnnotationRenderer.render(original, annotations)
    }
}

/// What the screen hands back to the caller on save.
struct IssueDraft {
    var checkpoint: IssueOption
    var description: IssueOption
    var issueDescription: String
    var technique: String
    var recommendation: String
    var screenshots: [UIImage]
}

// MARK: - View model

@MainActor @Observable
final class AddIssueViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    // Form values
    var checkpoint: IssueOption?
    var descriptionOption: IssueOption?
    var issueDescription = ""
    var technique = ""
    var recommendation = ""
    var screenshots: [Screenshot] = []
    var showErrors = false

    // Loaded options
    var checkpoints: [IssueOption] = []
    var descriptions: [IssueOption] = []
    var techniques: [String] = []
    var checkpointsState: LoadState = .idle
    var detailsState: LoadState = .idle      // descriptions + techniques for the chosen checkpoint

    var isSaving = false
    var saveError: String?

    @ObservationIgnored private let service: IssueOptionsService
    @ObservationIgnored private var detailsTask: Task<Void, Never>?

    init(service: IssueOptionsService) {
        self.service = service
    }

    // MARK: Loading

    /// Load errors stay hidden on launch; they only show after the user taps to retry and it fails again.
    var checkpointLoadErrorVisible = false
    var detailsLoadErrorVisible = false

    func loadCheckpoints(userInitiated: Bool = false) async {
        guard checkpointsState != .loading else { return }
        checkpointsState = .loading
        do {
            checkpoints = try await service.fetchCheckpoints()
            checkpointsState = .loaded
            checkpointLoadErrorVisible = false
        } catch {
            checkpointsState = Task.isCancelled ? .idle : .failed
            checkpointLoadErrorVisible = userInitiated && checkpointsState == .failed
        }
    }

    /// Call whenever `checkpoint` changes.
    func checkpointChanged() {
        detailsTask?.cancel()
        descriptionOption = nil
        technique = ""              // techniques depend on the checkpoint
        descriptions = []
        techniques = []
        guard checkpoint != nil else { detailsState = .idle; return }
        reloadDetails()
    }

    func reloadDetails(userInitiated: Bool = false) {
        guard let checkpoint else { return }
        detailsTask?.cancel()
        detailsState = .loading
        detailsTask = Task { await loadDetails(for: checkpoint, userInitiated: userInitiated) }
    }

    private func loadDetails(for requested: IssueOption, userInitiated: Bool) async {
        do {
            async let d = service.fetchDescriptions(checkpointID: requested.id)
            async let t = service.fetchTechniques(checkpointID: requested.id)
            let loadedDescriptions = try await d
            let loadedTechniques = (try? await t) ?? []      // suggestions are optional
            guard checkpoint == requested else { return }    // user moved on
            descriptions = loadedDescriptions
            techniques = loadedTechniques
            detailsState = .loaded
            detailsLoadErrorVisible = false
        } catch {
            guard checkpoint == requested, !Task.isCancelled else { return }
            detailsState = .failed
            detailsLoadErrorVisible = userInitiated
        }
    }

    func loadError(for field: IssueField) -> String? {
        switch field {
        case .checkpoint where checkpointsState == .failed && checkpointLoadErrorVisible:
            return "Couldn't load checkpoints. Tap to retry."
        case .technique where detailsState == .failed && detailsLoadErrorVisible:
            return "Couldn't load techniques. Tap to retry."
        case .description where detailsState == .failed && detailsLoadErrorVisible:
            return "Couldn't load descriptions. Tap to retry."
        default:
            return nil
        }
    }

    func isValid(_ field: IssueField) -> Bool {
        switch field {
        case .checkpoint: checkpoint != nil
        case .description: descriptionOption != nil
        case .issueDescription: !issueDescription.trimmed.isEmpty
        case .technique: !technique.trimmed.isEmpty
        case .recommendation: !recommendation.trimmed.isEmpty
        case .screenshots: !screenshots.isEmpty
        }
    }

    func error(for field: IssueField) -> String? {
        guard showErrors, !isValid(field) else { return nil }
        switch field {
        case .checkpoint: return "Choose a checkpoint"
        case .description: return "Choose a description"
        case .issueDescription: return "Describe the issue"
        case .technique: return "Select or enter a technique"
        case .recommendation: return "Describe how to fix it"
        case .screenshots: return "Add at least one screenshot"
        }
    }

    /// True once the user has entered anything, so Cancel can confirm before discarding.
    var hasChanges: Bool {
        checkpoint != nil || descriptionOption != nil
            || !issueDescription.trimmed.isEmpty
            || !technique.trimmed.isEmpty
            || !recommendation.trimmed.isEmpty
            || !screenshots.isEmpty
    }

    var completedCount: Int { IssueField.allCases.filter(isValid).count }
    var totalCount: Int { IssueField.allCases.count }
    var firstInvalid: IssueField? { IssueField.allCases.first { !isValid($0) } }

    /// Validates, then submits. Returns the draft on success, nil if invalid or the request failed.
    func save() async -> IssueDraft? {
        guard !isSaving, let draft = makeDraft() else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.submit(draft)
            return draft
        } catch {
            saveError = "Couldn't save the issue. Check your connection and try again."
            return nil
        }
    }

    /// Returns nil (and turns on inline errors) if anything required is missing.
    func makeDraft() -> IssueDraft? {
        showErrors = true
        guard let checkpoint, let descriptionOption, firstInvalid == nil else { return nil }
        return IssueDraft(
            checkpoint: checkpoint,
            description: descriptionOption,
            issueDescription: issueDescription.trimmed,
            technique: technique.trimmed,
            recommendation: recommendation.trimmed,
            screenshots: screenshots.map(\.rendered)
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
