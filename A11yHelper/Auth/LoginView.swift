import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        VStack(alignment: .center, spacing: 50) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "accessibility")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)

                Text("A11y Helper")
                    .font(.title2.weight(.semibold))

                Text("Sign in with your Deque Google account to report and track accessibility issues.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 6) {
                if let message = auth.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                // Official Google button from the SDK (logo, text and styling are Google's).
                GoogleSignInButton(scheme: .dark,
                                   style: .wide,
                                   state: auth.activeProvider == nil ? .normal : .disabled) {
                    Task { await auth.signIn(with: .google) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)          // GIDSignInButton's fixed height
                .overlay {
                    if auth.activeProvider == .google { ProgressView() }
                }

                Text("By continuing, you agree to the Terms and Privacy Policy.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.all, 12)
        .background(Color(.systemBackground))
        .onChange(of: auth.errorMessage) { _, message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}
