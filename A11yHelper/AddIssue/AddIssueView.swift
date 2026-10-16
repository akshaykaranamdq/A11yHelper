import SwiftUI
import UIKit
import PhotosUI

/// Full-screen "New issue" form. Push it onto a NavigationStack (not a modal).
/// iOS 17+.
struct AddIssueView: View {
    /// Hook into your existing capture flow. Pass nil to hide the Capture tile.
    var captureScreenshot: (() async -> UIImage?)?
    /// Optional. The view submits the issue itself and dismisses on success.
    var onSave: ((IssueDraft) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var vm: AddIssueViewModel
    @State private var activeSheet: PickerSheet?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var editing: Screenshot?
    @State private var showDiscardDialog = false
    @State private var scrollTarget: IssueField?
    @State private var longTextField: LongTextField?
    @FocusState private var focus: IssueField?

    /// `AddIssueView()` needs no inputs; it fetches everything itself on appear.
    init(service: IssueOptionsService = IssueOptionsEnvironment.service,
         captureScreenshot: (() async -> UIImage?)? = nil,
         onSave: ((IssueDraft) -> Void)? = nil) {
        _vm = State(initialValue: AddIssueViewModel(service: service))
        self.captureScreenshot = captureScreenshot
        self.onSave = onSave
    }

    private enum PickerSheet: String, Identifiable {
        case checkpoint, description, technique
        var id: String { rawValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Classification") {
                        FormRow(title: "Checkpoint",
                                error: vm.loadError(for: .checkpoint) ?? vm.error(for: .checkpoint)) {
                            PickerButton(title: "Checkpoint",
                                         value: vm.checkpoint?.title,
                                         placeholder: vm.checkpointsState == .loading ? "Loading…" : "Select checkpoint",
                                         isLoading: vm.checkpointsState == .loading) {
                                if vm.checkpointsState == .failed {
                                    Task { await vm.loadCheckpoints(userInitiated: true) }
                                } else {
                                    activeSheet = .checkpoint
                                }
                            }
                        }
                        .id(IssueField.checkpoint)
                        Divider().padding(.leading, 14)
                        FormRow(title: "Description",
                                error: vm.loadError(for: .description) ?? vm.error(for: .description)) {
                            PickerButton(title: "Description",
                                         value: vm.descriptionOption?.title,
                                         placeholder: descriptionPlaceholder,
                                         isLoading: vm.detailsState == .loading,
                                         isEnabled: vm.checkpoint != nil) {
                                if vm.detailsState == .failed {
                                    vm.reloadDetails(userInitiated: true)
                                } else {
                                    activeSheet = .description
                                }
                            }
                        }
                        .id(IssueField.description)
                    }

                    section("What's wrong") {
                        FormRow(title: "Issue description", error: vm.error(for: .issueDescription)) {
                            longTextPreview(.issueDescription)
                        }
                        .id(IssueField.issueDescription)
                    }

                    section("How to fix it") {
                        FormRow(title: "Recommendation technique",
                                error: vm.loadError(for: .technique) ?? vm.error(for: .technique)) {
                            techniqueRow
                        }
                        .id(IssueField.technique)
                        Divider().padding(.leading, 14)
                        FormRow(title: "Recommendation to fix", error: vm.error(for: .recommendation)) {
                            longTextPreview(.recommendation)
                        }
                        .id(IssueField.recommendation)
                    }

                    section("Screenshots", trailing: "\(vm.screenshots.count) attached", required: true) {
                        screenshotStrip
                        VStack(alignment: .leading, spacing: 4) {
                            if let error = vm.error(for: .screenshots) {
                                Label(error, systemImage: "exclamationmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            Text("Tap a screenshot to highlight elements with boxes and arrows.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                    .id(IssueField.screenshots)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .pinnedTopBar { progressHeader }      // stays pinned while the form scrolls
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
            .fullScreenCover(item: $longTextField) { field in
                NavigationStack {
                    LongTextEditor(text: longTextBinding(field),
                                   title: field.title,
                                   placeholder: field.placeholder)
                }
            }
        }
        .navigationTitle("New issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if vm.hasChanges { showDiscardDialog = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if vm.isSaving {
                    ProgressView()
                        .accessibilityLabel("Saving")
                } else {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .glassProminentIfAvailable()
                        .accessibilityLabel("Save issue")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .alert("Discard this issue?", isPresented: $showDiscardDialog) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("What you've entered will be lost.")
        }
        .task { await vm.loadCheckpoints() }
        .alert("Couldn't save", isPresented: Binding(get: { vm.saveError != nil },
                                                     set: { if !$0 { vm.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.saveError ?? "")
        }
        .onChange(of: vm.checkpoint) { _, _ in vm.checkpointChanged() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .checkpoint:
                SearchablePickerSheet(title: "Checkpoint", options: vm.checkpoints, selection: $vm.checkpoint)
            case .description:
                SearchablePickerSheet(title: "Description", options: vm.descriptions, selection: $vm.descriptionOption)
            case .technique:
                SearchablePickerSheet(title: "Technique",
                                      options: vm.techniques.map { IssueOption($0) },
                                      selection: techniqueBinding,
                                      searchable: false)
            }
        }
        .fullScreenCover(item: $editing) { shot in
            ImageAnnotationView(image: shot.original, annotations: shot.annotations) { result in
                if let i = vm.screenshots.firstIndex(where: { $0.id == shot.id }) {
                    vm.screenshots[i].apply(result)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
    }

    private var descriptionPlaceholder: String {
        if vm.checkpoint == nil { return "Choose a checkpoint first" }
        return vm.detailsState == .loading ? "Loading…" : "Select description"
    }

    // MARK: Progress

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(vm.completedCount), total: Double(vm.totalCount))
                .tint(vm.completedCount == vm.totalCount ? .green : .accentColor)
                .animation(.easeOut(duration: 0.2), value: vm.completedCount)
            Text("\(vm.completedCount) of \(vm.totalCount) required fields")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.completedCount) of \(vm.totalCount) required fields completed")
    }

    // MARK: Fields

    /// Tapping opens the full-screen editor; the field itself just previews the text.
    private func longTextBinding(_ field: LongTextField) -> Binding<String> {
        switch field {
        case .issueDescription: $vm.issueDescription
        case .recommendation: $vm.recommendation
        }
    }

    private func longTextPreview(_ field: LongTextField) -> some View {
        let text = longTextBinding(field).wrappedValue
        return Button {
            longTextField = field
        } label: {
            Text(text.isEmpty ? field.placeholder : text)
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(6)
                .frame(maxWidth: .infinity, minHeight: field.previewMinHeight, alignment: .topLeading)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(field.title), required")
        .accessibilityValue(text.isEmpty ? "Empty" : text)
        .accessibilityHint("Opens a full-screen editor")
    }

    private var techniqueBinding: Binding<IssueOption?> {
        Binding(
            get: { vm.technique.isEmpty ? nil : IssueOption(vm.technique) },
            set: { vm.technique = $0?.title ?? "" }
        )
    }

    private var techniquePlaceholder: String {
        if vm.checkpoint == nil { return "Choose a checkpoint first" }
        return vm.detailsState == .loading ? "Loading…" : "Select technique"
    }

    /// A dropdown like Checkpoint. If the API returns no techniques for a checkpoint,
    /// it falls back to a free-text field so the required field can still be filled.
    @ViewBuilder
    private var techniqueRow: some View {
        if vm.detailsState == .loaded && vm.techniques.isEmpty {
            techniqueField
        } else {
            PickerButton(title: "Recommendation technique",
                         value: vm.technique.isEmpty ? nil : vm.technique,
                         placeholder: techniquePlaceholder,
                         isLoading: vm.detailsState == .loading,
                         isEnabled: vm.checkpoint != nil,
                         hint: "Opens a list") {
                if vm.detailsState == .failed {
                    vm.reloadDetails(userInitiated: true)
                } else {
                    activeSheet = .technique
                }
            }
        }
    }

    /// Free-text fallback (with a menu of suggestions, when there are any).
    private var techniqueField: some View {
        HStack(spacing: 0) {
            TextField("Select or type a technique", text: $vm.technique)
                .focused($focus, equals: .technique)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .frame(minHeight: 28)
            if !vm.techniques.isEmpty {
                Menu {
                    ForEach(vm.techniques, id: \.self) { suggestion in
                        Button(suggestion) { vm.technique = suggestion }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Technique suggestions")
            }
        }
    }

    // MARK: Screenshots

    private var screenshotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let capture = captureScreenshot {
                    Button {
                        Task { if let img = await capture() { vm.screenshots.append(Screenshot(image: img)) } }
                    } label: {
                        AddTile(icon: "camera", title: "Capture")
                    }
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 15, matching: .images) {
                    AddTile(icon: "photo", title: "Library")
                }
                ForEach(Array(vm.screenshots.enumerated()), id: \.element.id) { index, shot in
                    thumbnail(shot, number: index + 1)
                }
            }
            .padding(14)
        }
    }

    private func thumbnail(_ shot: Screenshot, number: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { editing = shot } label: {
                Image(uiImage: shot.rendered)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                            .font(.title3)
                            .padding(4)
                    }
            }
            .accessibilityLabel("Screenshot \(number)")
            .accessibilityHint("Opens the editor to highlight elements")

            Button {
                withAnimation { vm.screenshots.removeAll { $0.id == shot.id } }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.75))
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .offset(x: 14, y: -14)
            .accessibilityLabel("Remove screenshot \(number)")
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                vm.screenshots.append(Screenshot(image: image))
            }
        }
        pickerItems = []
    }

    // MARK: Save

    private func save() {
        focus = nil
        Task {
            if let draft = await vm.save() {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSave?(draft)
                dismiss()
            } else if let first = vm.firstInvalid {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                scrollTarget = first
                let missing = vm.totalCount - vm.completedCount
                UIAccessibility.post(notification: .announcement,
                                     argument: "\(missing) required fields need attention")
            }
        }
    }

    // MARK: Layout helpers

    private func section<Content: View>(_ title: String,
                                        trailing: String? = nil,
                                        required: Bool = false,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 2) {
                    Text(title).foregroundStyle(.secondary)
                    if required { Text("*").foregroundStyle(.red).accessibilityHidden(true) }
                }
                .font(.footnote)
                Spacer()
                if let trailing { Text(trailing).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0, content: content)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Subviews

private struct FormRow<Content: View>: View {
    let title: String
    var error: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(title)
                Text("*").foregroundStyle(.red).accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            content

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PickerButton: View {
    let title: String
    let value: String?
    let placeholder: String
    var isLoading = false
    var isEnabled = true
    var hint = "Opens a searchable list"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(value ?? placeholder)
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel("\(title), required")
        .accessibilityValue(value ?? "Not selected")
        .accessibilityHint(hint)
    }
}

private struct AddTile: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption)
        }
        .foregroundStyle(.tint)
        .frame(width: 76, height: 96)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(Color.accentColor.opacity(0.5))
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AddIssueView(
            service: MockIssueOptionsService(),
            captureScreenshot: { UIImage(systemName: "photo") },
            onSave: { print($0) }
        )
    }
}
