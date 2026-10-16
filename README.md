# A11y Helper

An iOS app for reporting accessibility issues found while testing mobile apps. Testers pick a checkpoint, describe the problem and the fix, attach annotated screenshots, and see their reported issues on a Home list.

Built with SwiftUI. Supports iOS 18.6 and later, with Liquid Glass styling on iOS 26.

## Features

- **Home**: a list of recently reported issues (checkpoint, description, thumbnail, time), a floating "+" button to report a new one, and a confirmation banner after saving.
- **Report an issue** (full-screen form):
  - Searchable dropdowns for Checkpoint and Description. Techniques load for the chosen checkpoint.
  - Long text fields (issue description, recommendation) open in a full-screen editor, with no length limit.
  - Required-field progress bar pinned at the top, inline validation, and Save in the navigation bar.
  - At least one screenshot is required. Add from the photo library or a capture flow.
  - Asks before discarding unsaved changes.
- **Image annotation**: draw boxes and arrows on a screenshot, pick any color (presets plus the system color picker with eyedropper), move and resize shapes, delete, and undo. Annotations stay editable after saving.
- **Sign-in** (currently parked): Google sign-in restricted to Deque accounts.
- **Accessibility**: VoiceOver labels, hints and announcements, 44pt touch targets, and Dynamic Type friendly layouts.

## Requirements

- Xcode with the iOS 26 SDK
- iOS 18.6+ deployment target
- Swift Package: [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) (`GoogleSignIn` and `GoogleSignInSwift`), resolved automatically by Xcode

## Getting started

1. Clone the repo and open `A11yHelper.xcodeproj`.
2. Let Xcode resolve the Swift packages.
3. Pick a simulator or device and run.

The app opens on Home with sample data. No account or backend is needed to try the issue form.

## Configuration

Two switches control how much of the app is "live". Both are in code.

| Setting | File | Default | What it does |
|---|---|---|---|
| `IssueOptionsEnvironment.useSampleData` | `AddIssue/IssueOptionsService.swift` | `true` | `true` uses built-in sample checkpoints, descriptions and techniques. `false` calls the real API. |
| `RootView.requireLogin` | `Auth/RootView.swift` | `false` | `true` shows the login screen first. `false` opens straight on Home. |

### Connecting the API

Everything API-specific lives in `AddIssue/IssueOptionsService.swift`:

- Set the real base URL and headers in `APIIssueOptionsService.live`.
- Adjust the endpoint paths and the `OptionDTO` response shape to match the backend. They are placeholders for now:
  - `GET checkpoints`
  - `GET checkpoints/{id}/descriptions`
  - `GET checkpoints/{id}/techniques`
  - `POST issues`
- Set `useSampleData = false`.

### Enabling Google sign-in

1. In Google Cloud Console, create an OAuth client of type **iOS** with bundle ID `com.ak.A11yHelper`. Use a project in the Deque Google Workspace, with the consent screen set to **Internal**.
2. Paste the client ID into `GoogleAuthService.clientID` (`Auth/GoogleAuthService.swift`).
3. In the target's **Info** tab, add a URL Type whose scheme is the reversed client ID (`com.googleusercontent.apps.<your-number>`).
4. Set `RootView.requireLogin = true`.

Access is limited to the domains in `AuthPolicy.allowedDomains` (`deque.com`). The in-app check is a convenience. The backend must verify the Google ID token and enforce access. `AuthManager.idToken()` returns a fresh token for API calls.

## Project structure

```
A11yHelper/
├── A11yHelperApp.swift          App entry point, starts at RootView
├── ContentView.swift            Home: issue list, + button, saved banner
├── Home/
│   ├── IssueStore.swift         In-memory list of reported issues (sample-seeded)
│   └── IssueRow.swift           One row in the Home list
├── AddIssue/
│   ├── AddIssueView.swift       The report form
│   ├── AddIssueModels.swift     View model, validation, IssueDraft
│   ├── IssueOptionsService.swift  API client, mock data, environment switch
│   ├── SearchablePickerSheet.swift  Dropdown sheet (optional search)
│   ├── LongTextEditor.swift     Full-screen text editor for long fields
│   └── ImageAnnotationView.swift  Screenshot annotation editor
├── Auth/
│   ├── RootView.swift           Chooses Login or Home
│   ├── AuthManager.swift        Auth state, domain policy
│   ├── GoogleAuthService.swift  GoogleSignIn wrapper
│   └── LoginView.swift          Login screen
└── Support/
    └── Compat.swift             iOS 26 styling with iOS 18.6 fallbacks
```

## Architecture notes

- **State**: `@Observable` view models (`AddIssueViewModel`, `AuthManager`, `IssueStore`). Views hold them in `@State`.
- **Data access**: the form talks to the `IssueOptionsService` protocol, with an API implementation and a mock, so the UI doesn't change when the backend is ready.
- **Loading**: checkpoints load on appear. Descriptions and techniques load when a checkpoint is chosen, and a stale response for a previous checkpoint is ignored. Load errors stay quiet until the user retries.
- **Annotations**: shapes are stored with normalized coordinates (0 to 1) and flattened onto the full-resolution image on save, so they survive any screen size.
- **OS versions**: all iOS 26-only APIs are wrapped in `Support/Compat.swift`. Add new `#available(iOS 26, *)` checks there.

## Known limitations

- Reported issues are held in memory, so they don't persist across launches.
- Home rows don't open a detail screen yet.
- The Capture tile in the form is hidden until a capture flow is passed to `AddIssueView(captureScreenshot:)`.
- API endpoints and the submit payload are placeholders until the backend contract is confirmed.
