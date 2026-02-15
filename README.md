# Jin

Native macOS LLM client built with SwiftUI and SwiftData.

## Build and Run

- Build: `swift build`
- Test: `swift test`
- Run: `swift run Jin`

## Packaging

- Build `.app`: `bash Packaging/package.sh`
- Build `.dmg`: `bash Packaging/package.sh dmg`

## Opening the App on macOS

If macOS shows a warning like "is damaged and can't be opened", it is usually a Gatekeeper block on an unsigned/unnotarized build.

1. Open the DMG and drag `Jin.app` into `/Applications`.
2. In Finder, Control-click `Jin.app` and choose **Open**.
3. Click **Open** again in the dialog.
4. If it is still blocked, remove quarantine attributes:

```bash
xattr -dr com.apple.quarantine /Applications/Jin.app
```

If the DMG itself is blocked, run:

```bash
xattr -dr com.apple.quarantine ~/Downloads/Jin.dmg
```

Only use these commands for builds from a source you trust.
