//
//  ContentView.swift  (Home)
//  A11yHelper
//
//  Created by DQ_Akshay on 15/10/26.
//

import SwiftUI

struct ContentView: View {
    /// Optional so Home also works while login is parked.
    @Environment(AuthManager.self) private var auth: AuthManager?

    @State private var store = IssueStore()
    @State private var showAddIssue = false
    @State private var toast: String?

    private var signedInUser: UserProfile? {
        if case .signedIn(let user)? = auth?.state { return user }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.issues.isEmpty {
                    ContentUnavailableView("Report your first issue",
                                           systemImage: "checklist",
                                           description: Text("Issues you report show up here."))
                } else {
                    issueList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Issues")
            .toolbar { accountMenu }
            .overlay(alignment: .bottomTrailing) { reportButton }
            .overlay(alignment: .top) { toastBanner }
            .fullScreenCover(isPresented: $showAddIssue) {
                NavigationStack {
                    AddIssueView(onSave: { draft in
                        store.add(draft)
                        showToast("Issue saved")
                    })
                }
            }
        }
    }

    // MARK: Pieces

    private var issueList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Text(store.issues.count == 1 ? "1 recent issue" : "\(store.issues.count) recent issues")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                ForEach(store.issues) { issue in
                    IssueRow(issue: issue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 88)       // room so the last row clears the + button
        }
    }

    private var reportButton: some View {
        Button {
            showAddIssue = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Report new issue")
        .padding(.trailing, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var accountMenu: some ToolbarContent {
        if let user = signedInUser {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !user.email.isEmpty { Text(user.email) }
                    Button("Sign out", role: .destructive) { auth?.signOut() }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Account")
            }
        }
    }

    // MARK: Toast

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }
}

#Preview {
    ContentView()
}
