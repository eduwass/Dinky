# Releases

Run `just release 0.1.1` from a clean, pushed `main`. It runs the tests, builds an arm64 release bundle, signs it with your Developer ID Application identity with the hardened runtime, notarizes and staples it using the `TunaNotary` keychain profile, zips it to `dist/dinky.app.zip`, tags `v0.1.1`, creates a draft GitHub release with generated notes, uploads the zip and publishes it as latest. Running it again retries a failed release; a published version is never replaced.

`just package 0.1.1` does everything up to and including the zip without publishing. Override `NOTARYTOOL_PROFILE` or `DEVELOPER_ID_APPLICATION` when needed. The build number is the commit count plus 100. macOS 27 runs on Apple silicon only, so releases are not universal.
