# Releasing Tidy

Tidy releases are built, signed with a Developer ID certificate, notarized by
Apple, packaged as a DMG, and attached to a GitHub release by
`.github/workflows/release.yml`.

## One-time repository setup

Add these encrypted GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID |
| `DEVELOPER_ID_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Random password used for the temporary CI keychain |

The certificate secret can be prepared locally with:

```sh
base64 -i DeveloperID.p12 | pbcopy
```

## Publish a release

1. Update `CHANGELOG.md` and the Xcode marketing/build versions.
2. Ensure CI is green on `main`.
3. Create and push a signed version tag, for example `v1.1.0`.
4. Verify the GitHub release contains `Tidy.dmg` and its SHA-256 file.
5. Install the DMG on a clean macOS user account and verify Accessibility,
   Keychain, clipboard, and network-provider flows.

The release workflow fails closed when any signing or notarization secret is
missing. Pull requests never receive release secrets.
