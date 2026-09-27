# Releases

Run `just release 0.1.1` from a clean, pushed `main`. It runs the tests, builds an arm64 release bundle, signs it with your Developer ID Application identity with the hardened runtime, notarizes and staples it using the `TunaNotary` keychain profile, zips it to `dist/dinky.app.zip`, signs the zip for Sparkle and writes `dist/appcast.xml`, writes `dist/dinky.rb` from `scripts/dinky.rb.template`, tags `v0.1.1`, creates a draft GitHub release with generated notes, uploads the zip, the appcast and the cask, publishes it as latest, and pushes the cask to [mikker/homebrew-tap](https://github.com/mikker/homebrew-tap) through a temporary clone. Running it again retries a failed release or tap update; a published version is never replaced.

`just package 0.1.1` does everything up to and including the zip, appcast and cask without publishing. Override `NOTARYTOOL_PROFILE` or `DEVELOPER_ID_APPLICATION` when needed. The build number is the commit count plus 100. macOS 27 runs on Apple silicon only, so releases are not universal.

## Updates

dinky updates itself with [Sparkle](https://sparkle-project.org) (SwiftPM package, `Sparkle.framework` in `Contents/Frameworks`, signed inside out by `scripts/bundle.sh`). The feed, `SUFeedURL` in `Resources/Info.plist`, is https://github.com/mikker/Dinky/releases/latest/download/appcast.xml: the `appcast.xml` asset of the latest release, so publishing a release is what ships the update. `scripts/appcast.py` writes it from the built app and the zip.

Updates are signed with an EdDSA key whose private half lives in the login Keychain under the account `com.brnbw.dinky`; `sign_update --account com.brnbw.dinky` uses it during packaging. The public key, `SUPublicEDKey`, is `jif/E57Xw8xCo7BwHnOeASD+nbQc462aQTYOuvoH/io=`. Losing the private key means installed copies can no longer update, so keep a backup somewhere safe:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x dinky-sparkle-key --account com.brnbw.dinky
```

Import it on another Mac with `generate_keys -f dinky-sparkle-key --account com.brnbw.dinky`.
