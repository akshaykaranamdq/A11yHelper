import SwiftUI
import GoogleSignIn

/// Chooses between loading, Login and Home based on auth state.
struct RootView: View {
    /// Login is parked while its setup is pending. Set to `true` to bring it back.
    static let requireLogin = false

    @State private var auth = AuthManager()

    var body: some View {
        Group {
            if Self.requireLogin {
                switch auth.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .signedOut:
                    LoginView()
                case .signedIn:
                    ContentView()      // Home
                }
            } else {
                ContentView()          // Home
            }
        }
        .environment(auth)
        .animation(.default, value: auth.state)
        .task { if Self.requireLogin { await auth.restore() } }
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}
