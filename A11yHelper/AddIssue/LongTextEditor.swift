import SwiftUI

/// The long-text fields on the New issue form that open in a full-screen editor.
enum LongTextField: Identifiable {
    case issueDescription, recommendation

    var id: String { String(describing: self) }

    var title: String {
        switch self {
        case .issueDescription: "Issue description"
        case .recommendation: "Recommendation to fix"
        }
    }

    var placeholder: String {
        switch self {
        case .issueDescription: "Describe what happens and where"
        case .recommendation: "Add .accessibilityLabel(\"Close\") to the button"
        }
    }

    var previewMinHeight: CGFloat {
        switch self {
        case .issueDescription: 96
        case .recommendation: 72
        }
    }
}

/// Full-screen text editor. No length limit.
struct LongTextEditor: View {
    @Binding var text: String
    let title: String
    let placeholder: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 21)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
//                .sharedBackgroundVisibility(.hidden)
            }
            .onAppear { isFocused = true }
    }
}

#Preview {
    NavigationStack {
        LongTextEditor(text: .constant(""),
                       title: LongTextField.issueDescription.title,
                       placeholder: LongTextField.issueDescription.placeholder)
    }
}
