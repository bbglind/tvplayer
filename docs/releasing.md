# Releasing tvplayer

Releases are built locally and uploaded to a GitHub Release by hand.

**A release is built only from `main`, after the branch is merged, and its tag
(e.g. `v0.1.0`) must point to that same commit.** The script also builds on
another branch, for testing, but then ends with a warning not to upload.

## One-time setup: signing

The keystore lives outside the repo. Never commit or move it into the repo.

```sh
cp android/key.properties.example android/key.properties
chmod 600 android/key.properties
```

Then edit `android/key.properties`: `storeFile` is the absolute path to the
keystore (or starts with `~/`), and the passwords are typed in by hand. The file
is gitignored. Without it, `tool/package_release.sh` refuses to run, and
any other release build is debug-signed with a warning.

To compare the signature later, get the keystore's fingerprint (asks for the
password):

```sh
keytool -list -v -keystore <keystore> -alias <alias> | grep 'SHA256:'
```

Optionally, copy `tool/release-denylist.example.txt` to
`tool/release-denylist.local.txt` (gitignored) and list your own domains and IP
addresses. The script then fails if it finds any of them in a release.

## Making a release

1. **Bump the version** in `pubspec.yaml`, e.g. `0.1.0+1`. Raise the part after
   the `+` every release: Android refuses to update to a lower number, and apt
   sorts on it too. The part before it goes in the file names. Three more
   places: `version` in `packages/tvplayer_sync_server/pubspec.yaml`,
   `serverVersion` in `packages/tvplayer_sync_server/lib/src/api.dart` (a test
   keeps these equal), and the `releases/download/v<version>/` addresses in
   `docs/sync-server.md` (the build refuses otherwise).
2. **Merge to `main`** and make sure the tree is clean:

   ```sh
   git switch main
   git status
   ```

3. **Build:**

   ```sh
   tool/package_release.sh
   ```

   It exports `HEAD` to `/tmp/tvplayer-release` (so no local files or home folder
   paths get in), builds everything, checks it and fills `dist/`:

   - `tvplayer_<version>_amd64.deb`
   - `tvplayer-<version>.apk`
   - `tvplayer-sync-server_<version>_linux-amd64.tar.gz`: the sync server
   - `tvplayer-sync-proxmox.sh`: its installer, with this version pinned inside
     it. It downloads from this release's own address, not `/releases/latest`,
     because a pre-release is never "latest".
   - `SHA256SUMS`

   The script refuses to finish when the APK isn't signed with your own key,
   lacks an architecture, the server reports another version, or any file
   contains personal data. Install `shellcheck` to have the installer checked
   too; without it the script only warns. The summary at the end
   shows the commit, short and full, and the signer.
4. **Verify:**
   - Read through the URL hosts and IPs the script prints.
   - Compare "Signer SHA-256" with the `keytool` fingerprint above. To check the
     APK in `dist/` again later:

     ```sh
     ~/Android/Sdk/build-tools/36.0.0/apksigner verify --print-certs dist/tvplayer-<version>.apk
     ```

   - Install the `.deb` and try it.
   - Check the checksums, the server archive and the pinned version:

     ```sh
     (cd dist && sha256sum -c SHA256SUMS)
     tar -tzf dist/tvplayer-sync-server_<version>_linux-amd64.tar.gz
     grep '^release_version=' dist/tvplayer-sync-proxmox.sh
     ```

     The archive lists `bundle/bin/tvplayer_sync_server`, `bundle/lib/`,
     `bundle/deploy/` and `bundle/config.example.json`.
   - Run `tool/proxmox/test_installer.sh dist/tvplayer-sync-server_<version>_linux-amd64.tar.gz`
     (needs `bwrap` and `script`). It tries the installer in a sandbox with stand-ins for the
     Proxmox tools, so also try a change to the installer on a real Proxmox host:
     copy `dist/` there and use `--local` (see `docs/sync-server.md`).
5. **Tag** the commit from the summary:

   ```sh
   git tag v<version> <full commit>
   git rev-parse 'v<version>^{commit}'
   ```

   The second command must print the same hash as "Commit (full)". Push `main`
   and the tag.
6. **Create the GitHub Release:** on the repo's Releases page choose "Draft a new
   release", pick the tag, tick "Set as a pre-release", attach the five files
   from `dist/` and publish.

## Keep these safe

Back up, separately and outside the repo:

- the keystore
- its password

Android only installs an update signed with the same key. If either is lost,
no update can reach existing users: they must uninstall, which deletes the app's
data on their phone, and install a build signed with a new key.

## Switching from a debug-signed install

Earlier APKs and `flutter run --release` without `android/key.properties` are
debug-signed. Replacing a debug-signed install with the release-signed APK takes
**one uninstall**: Android refuses the update otherwise. The app's data on the
phone is lost, so login, TMDB key and sync token must be entered again, and files
downloaded in the app's folder go too.

Once `android/key.properties` exists, your own `flutter run --release` is
release-signed as well, so on a development phone this uninstall comes with the
first such run.

## Known limitations

- **Placeholder icon:** the app icon on Linux and Android is still the default
  Flutter logo (`android/app/src/main/res/mipmap-*/ic_launcher.png`; the `.deb`
  uses the 192 px one). That is accepted for test releases. **Replace it before a
  public release.**
- The `.deb` is built on and for Linux Mint 22 / Ubuntu 24.04 (noble). Its
  dependencies are worked out on the build machine, using that release's package
  names, so it won't install on older or differently named bases.
