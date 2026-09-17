# simple contributor notes

- This is a macOS SwiftUI app with one local terminal window.
- SwiftTerm is the sole runtime dependency; it provides terminal emulation and the local PTY.
- Keep the app small. Do not add settings, accounts, network services, Rust, or generated project files.
- Localize any new visible app copy; avoid adding interface text when the terminal itself is enough.
- Build with `swift build`; do not launch with `swift run`
- do not write tests
