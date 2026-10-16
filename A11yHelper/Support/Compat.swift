import SwiftUI

// iOS 26 adds Liquid Glass and a few new controls. The app supports iOS 18.6+, so each of them
// gets a graceful fallback here. Keep all `#available(iOS 26, *)` checks in this file.

extension View {
    /// Frosted capsule behind a control group: Liquid Glass on iOS 26+, a material before that.
    @ViewBuilder
    func pillBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Pins a view just below the navigation bar while the content scrolls underneath.
    /// iOS 26+: soft scroll-edge effect. Earlier: a bar-material strip.
    @ViewBuilder
    func pinnedTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let content = bar()
        if #available(iOS 26, *) {
            safeAreaBar(edge: .top) { content }
        } else {
            safeAreaInset(edge: .top, spacing: 0) { content.background(.bar) }
        }
    }

    /// Prominent button: glass on iOS 26+, standard filled style before that.
    @ViewBuilder
    func glassProminentIfAvailable() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// System close button on iOS 26+, an equivalent circled X before that.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .close, action: action)
        } else {
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
    }
}
