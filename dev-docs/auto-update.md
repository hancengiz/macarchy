# Auto-update (Sparkle)

Release builds update themselves from the GitHub releases feed.

## One-time setup (done 2026-09-28, except the secret)

- EdDSA key pair generated with Sparkle's `generate_keys`; the private key
  lives in the login keychain, the public key is embedded in `install.py`
  (`SUPublicEDKey`).
- **Left for the repo owner:** add the private key as the GitHub secret
  `SPARKLE_PRIVATE_KEY`:
  ```sh
  security find-generic-password -s "https://sparkle-project.org" -w \
    | pbcopy   # then paste as the SPARKLE_PRIVATE_KEY secret
  ```

## Flow

- `git tag v0.22.2 && git push --tags` → the release workflow builds with
  `--release` (keeps `SUFeedURL`/`SUPublicEDKey`), generates and signs
  `appcast.xml` with the secret key, and attaches both to the release.
- Installed release apps check `releases/latest/download/appcast.xml`,
  verify the EdDSA signature, and update via Sparkle.
- Personal builds (`install.py --build`, no `--release`) strip the updater
  keys: a locally built app never self-updates over the release channel.
- "Check for Updates…" lives in the tray menu.

## Notes

- CI release signing still needs the three `MACARCHY_*` secrets (see the
  workflow) — without them the artifact is ad-hoc signed and every release
  update resets the Accessibility grant.
