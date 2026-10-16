import SwiftUI

struct IssueRow: View {
    let issue: ReportedIssue

    private var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: issue.createdAt, relativeTo: .now)
    }

    private var screenshotText: String {
        switch issue.screenshots.count {
        case 0: "No screenshots"
        case 1: "1 screenshot"
        default: "\(issue.screenshots.count) screenshots"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(issue.checkpoint)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    Spacer(minLength: 8)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(issue.summary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(screenshotText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(issue.checkpoint). \(issue.summary)")
        .accessibilityValue("\(screenshotText), \(timeText)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = issue.screenshots.first {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 52, height: 64)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
