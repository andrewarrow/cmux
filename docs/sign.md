 Developers normally avoid this by keeping the app’s code identity stable:

  - Use a real Apple Development signing certificate.
  - Keep the same bundle ID forever.
  - Keep Debug/Release builds signed with the same identity.
  - Always replace the same .app bundle, rather than running an unsigned binary from .build.
  - Don’t use ad-hoc signing (codesign -s -), change bundle IDs, or alternate between Xcode, Terminal, and
    Developer ID builds.

  macOS records the app’s designated requirement, not just its file path, to decide whether a new build is the
  same app. citeturn1search0

  For this project, pin the signing identity so multiple certificates cannot accidentally switch the app’s
  identity:

  export SIMPLECMUX_SIGNING_IDENTITY='Apple Development: Andrew Arrow (3A9VAJ3AD7)'
  ./scripts/build-app.sh "$HOME/Desktop/SimpleCmux.app"

  After the first approval with this signed build, later source changes should not require re-approval.

  tccutil is only useful for intentionally resetting permissions during testing; it does not grant them.
  citeturn2search0

  The only normal way to pre-grant permissions is device management/MDM using a privacy policy profile, which is
  intended for managed Macs—not ordinary personal development machines. citeturn1search2
