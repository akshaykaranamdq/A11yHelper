import SwiftUI

/// Searchable single-select list shown as a sheet.
struct SearchablePickerSheet: View {
    let title: String
    let options: [IssueOption]
    @Binding var selection: IssueOption?
    /// Turn off for short lists that don't need a search field.
    var searchable = true

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [IssueOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.title).foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(OptionalSearch(enabled: searchable, text: $query))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct OptionalSearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text,
                               placement: .navigationBarDrawer(displayMode: .always),
                               prompt: "Search")
        } else {
            content
        }
    }
}
