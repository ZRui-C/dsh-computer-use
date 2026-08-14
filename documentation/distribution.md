# macOS distribution

Official releases are open-source builds delivered outside the Mac App Store as Developer ID signed and Apple-notarized Universal 2 DMGs.

## Local installer

```bash
pnpm install
pnpm run build
pnpm run package:dmg
```

This creates an ad-hoc or development-signed installer under `release/`. It is suitable for local verification, not public distribution.

Use a single architecture for faster development:

```bash
COMPUTER_USE_ARCHS=arm64 pnpm run build
```

`package:dmg` deliberately rejects non-Universal app bundles.

## Install a Developer ID certificate

You need the `Developer ID Application` certificate for the Apple Developer Program team that will publish the App. An Account Holder or Admin can create it; another team role needs the **Access to Certificates, Identifiers & Profiles** permission.

### Xcode, recommended

1. Open **Xcode > Settings > Accounts** and add the Apple ID enrolled in the team.
2. Select the team, open **Manage Certificates**, select `+`, then choose **Developer ID Application**.
3. Xcode creates the private key in the login keychain and installs the matching certificate.

### Apple Developer website

Use this route when Xcode cannot create the certificate:

1. Open **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority**.
2. Enter the Apple ID email and a descriptive common name, choose **Saved to disk**, and save the CSR.
3. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/add), choose **Developer ID Application**, and upload the CSR.
4. Download the `.cer` file and double-click it to import it into the login keychain.
5. In **Keychain Access > My Certificates**, expand the certificate and confirm that a private key appears underneath it.

A `.cer` file does not contain the private key. If no private key appears, the CSR was created on another Mac or the key was deleted; create a new certificate/CSR rather than trying to sign with the `.cer` alone.

Verify the installed identity:

```bash
security find-identity -v -p codesigning
```

The output must include a valid line beginning with `Developer ID Application:`. Keep the private key in the login keychain; do not commit or upload it.

### Export for GitHub Actions

In **Keychain Access > My Certificates**, right-click the Developer ID certificate, choose **Export**, select `.p12`, and set a strong temporary password. Encode it for the `MACOS_CERTIFICATE_P12` secret:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

The P12 password becomes `MACOS_CERTIFICATE_PASSWORD`. Delete unencrypted copies and securely archive the original P12 after the CI secret is configured.

## Notarization and release

After installing the certificate, store notarization credentials in a keychain profile:

```bash
xcrun notarytool store-credentials dsh-computer-use-notary \
  --apple-id 'release@example.com' \
  --team-id 'TEAMID' \
  --password 'app-specific-password'

COMPUTER_USE_CODESIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
  pnpm run build

COMPUTER_USE_CODESIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
NOTARYTOOL_PROFILE='dsh-computer-use-notary' \
  pnpm run release:macos
```

The release script:

1. verifies the nested app signature and both architectures;
2. notarizes a ZIP and staples the App;
3. creates a drag-to-Applications DMG;
4. signs, notarizes, and staples the DMG;
5. runs Gatekeeper assessment; and
6. writes a SHA-256 checksum.

App Store sandboxing is intentionally not enabled. The full product uses private SkyLight APIs for background targeted input and is not eligible for Mac App Store review.

## GitHub Actions secrets

For CI notarization, create a Team API key in **App Store Connect > Users and Access > Integrations > App Store Connect API**. Record the issuer ID and key ID, then download the `.p8` once; Apple does not offer a second download.

The tagged release workflow expects:

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | P12 password |
| `MACOS_KEYCHAIN_PASSWORD` | Ephemeral CI keychain password |
| `MACOS_CODESIGN_IDENTITY` | Full `Developer ID Application: ...` identity |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_P8` | P8 private key contents |

Never place these values in repository variables, source files, workflow logs, issue reports, or release assets.

## User upgrade behavior

Replacing the App in `/Applications` preserves the bundle ID and designated requirement. A release signed by the same Team ID normally retains TCC grants. Open the setup center after upgrading and select **Reinstall** to refresh the DSH file dependency, then restart the running DSH Host.
