import SwiftUI
import Observation

// MARK: - Policy

/// Who may use the app. Deque emails are Google accounts, so Google sign-in is the only login
/// and access is limited to these domains.
enum AuthPolicy {
    static let allowedDomains = ["deque.com"]

    /// Passed to Google so the account picker only offers these accounts.
    /// (Google accepts a single hosted domain; the check below covers the rest.)
    static var hostedDomain: String? {
        allowedDomains.count == 1 ? allowedDomains.first : nil
    }

    /// Exact domain match, case-insensitive. Subdomains don't count.
    static func isAllowed(email: String) -> Bool {
        guard let domain = email.split(separator: "@").last else { return false }
        return allowedDomains.contains(domain.lowercased())
    }
}

// MARK: - Models

enum AuthProvider: String, Hashable {
    case google
}

struct UserProfile: Equatable {
    var name: String
    var email: String
    var imageURL: URL?
    var provider: AuthProvider
}

enum AuthError: LocalizedError {
    case notConfigured
    case wrongDomain
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google sign-in isn't set up. Add the client ID in GoogleAuthService."
        case .wrongDomain: "Use your Deque Google account to sign in."
        case .cancelled: nil
        case .failed: "Couldn't sign in. Try again."
        }
    }
}

/// One implementation per provider.
@MainActor
protocol AuthService {
    /// Returns the profile if a previous session can be restored silently.
    func restore() async -> UserProfile?
    func signIn() async throws -> UserProfile
    func signOut()
    /// A fresh ID token for API calls, or nil if signed out.
    func idToken() async -> String?
}

// MARK: - Manager

@MainActor @Observable
final class AuthManager {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UserProfile)
    }

    private(set) var state: State = .loading
    /// Set while a sign-in is in progress, so the UI can show a spinner on that button.
    private(set) var activeProvider: AuthProvider?
    var errorMessage: String?

    @ObservationIgnored private let services: [AuthProvider: any AuthService]

    init(services: [AuthProvider: any AuthService]? = nil) {
        self.services = services ?? [.google: GoogleAuthService()]
    }

    func restore() async {
        for service in services.values {
            guard let profile = await service.restore() else { continue }
            if AuthPolicy.isAllowed(email: profile.email) {
                state = .signedIn(profile)
                return
            }
            service.signOut()      // a saved session from a non-Deque account
        }
        state = .signedOut
    }

    func signIn(with provider: AuthProvider) async {
        guard activeProvider == nil, let service = services[provider] else { return }
        activeProvider = provider
        errorMessage = nil
        defer { activeProvider = nil }

        do {
            let profile = try await service.signIn()
            guard AuthPolicy.isAllowed(email: profile.email) else {
                service.signOut()
                throw AuthError.wrongDomain
            }
            state = .signedIn(profile)
        } catch AuthError.cancelled {
            // User closed the sign-in sheet. Not an error.
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = AuthError.failed.errorDescription
        }
    }

    func signOut() {
        services.values.forEach { $0.signOut() }
        errorMessage = nil
        state = .signedOut
    }

    /// Fresh ID token for the signed-in user. Attach it to API requests once the backend is ready.
    func idToken() async -> String? {
        guard case .signedIn(let user) = state else { return nil }
        return await services[user.provider]?.idToken()
    }
}
