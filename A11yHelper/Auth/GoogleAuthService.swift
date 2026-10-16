import UIKit
import GoogleSignIn

/// Google sign-in through the official GoogleSignIn-iOS package.
@MainActor
final class GoogleAuthService: AuthService {
    /// TODO: paste the iOS OAuth client ID from Google Cloud Console
    /// (bundle ID: com.ak.A11yHelper). Looks like 1234-abc.apps.googleusercontent.com.
    /// The reversed form must also be added as a URL scheme (see setup steps).
    static let clientID = "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"

    private var isConfigured: Bool { !Self.clientID.hasPrefix("YOUR_") }

    init() {
        if isConfigured {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: Self.clientID,
                serverClientID: nil,
                hostedDomain: AuthPolicy.hostedDomain,     // account picker shows only Deque accounts
                openIDRealm: nil
            )
        }
    }

    func restore() async -> UserProfile? {
        guard isConfigured, GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
        guard let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn() else { return nil }
        return Self.profile(from: user)
    }

    func signIn() async throws -> UserProfile {
        guard isConfigured else { throw AuthError.notConfigured }
        guard let presenter = Self.topViewController() else { throw AuthError.failed }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            return Self.profile(from: result.user)
        } catch {
            let ns = error as NSError
            if ns.domain == kGIDSignInErrorDomain, ns.code == GIDSignInError.canceled.rawValue {
                throw AuthError.cancelled
            }
            throw AuthError.failed
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func idToken() async -> String? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        let refreshed = try? await user.refreshTokensIfNeeded()
        return (refreshed ?? user).idToken?.tokenString
    }

    // MARK: Helpers

    private static func profile(from user: GIDGoogleUser) -> UserProfile {
        UserProfile(
            name: user.profile?.name ?? "Google user",
            email: user.profile?.email ?? "",
            imageURL: user.profile?.imageURL(withDimension: 96),
            provider: .google
        )
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
