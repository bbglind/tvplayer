#!/usr/bin/env bash
# Builds the release files into dist/: tvplayer_<version>_amd64.deb,
# tvplayer-<version>.apk and SHA256SUMS. See docs/releasing.md. Needs no root.
#
# Builds from a clean export of HEAD in a neutral folder, because a build in
# the repo folder embeds its absolute path in libapp.so and the plugins. It
# also means only committed files can end up in a release.
set -euo pipefail
umask 022

app_id=io.github.bbglind.tvplayer
# The real WM_CLASS class of the window (g_set_prgname in my_application.cc).
wm_class=Io.github.bbglind.tvplayer
maintainer='tvplayer project <noreply@example.com>'
homepage=https://github.com/bbglind/tvplayer
# Not visible to dpkg-shlibdeps: mpv is started as a process, xdg-open too, the
# keyring is reached over D-Bus and epoxy dlopens EGL and GL.
extra_depends='mpv, gnome-keyring, xdg-utils, libegl1, libgl1'
build_tools=$HOME/Android/Sdk/build-tools/36.0.0
work=/tmp/tvplayer-release

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
apksigner=$build_tools/apksigner
denylist=tool/release-denylist.local.txt

# --- Prechecks, before anything is built ---

[ -f android/key.properties ] || die "android/key.properties is missing, so \
the APK would be debug-signed. See docs/releasing.md."
if [ "$(stat -c %a android/key.properties)" != 600 ]; then
  echo "WARNING: android/key.properties should have mode 600 (chmod 600 android/key.properties)."
fi
for tool in flutter git dpkg-deb dpkg-shlibdeps desktop-file-validate patchelf \
    readelf strings unzip sha256sum; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done
[ -x "$apksigner" ] || die "apksigner not found at $apksigner"
[ -z "$(git status --porcelain)" ] || die "the work tree has uncommitted \
changes; a release is built from a commit."

commit=$(git rev-parse HEAD)
commit_short=$(git rev-parse --short HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)
full_version=$(sed -n 's/^version: *//p' pubspec.yaml)
version=${full_version%%+*}
[[ $full_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] \
  || die "unexpected version in pubspec.yaml: $full_version"
deb_name=tvplayer_${version}_amd64.deb
apk_name=tvplayer-${version}.apk

step "Building $full_version from commit $commit_short ($branch)"
echo "Commit: $commit"

# --- Clean export ---

cleanup() { rm -rf "$work"; }
trap cleanup EXIT
rm -rf "$work"
mkdir -m 700 "$work"
src=$work/src
mkdir "$src"
git archive HEAD | tar -x -C "$src"
# A link, so the passwords aren't copied into /tmp.
ln -s "$root/android/key.properties" "$src/android/key.properties"

# --- Linux bundle ---

step "Building the Linux bundle"
(cd "$src" && flutter build linux --release)

pkg=$work/deb
opt=$pkg/opt/tvplayer
mkdir -p "$opt" "$pkg/DEBIAN" "$pkg/usr/bin" "$pkg/usr/share/applications" \
  "$pkg/usr/share/icons/hicolor/192x192/apps"
cp -r "$src/build/linux/x64/release/bundle/." "$opt/"

# The plugins carry the build folder as RUNPATH; the app doesn't need it.
for plugin in "$opt"/lib/lib*_plugin.so; do
  patchelf --set-rpath '$ORIGIN' "$plugin"
done

cat > "$pkg/usr/bin/tvplayer" <<'EOF'
#!/bin/sh
exec /opt/tvplayer/tvplayer "$@"
EOF

cat > "$pkg/usr/share/applications/$app_id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=tvplayer
Comment=IPTV player
Exec=tvplayer
Icon=$app_id
Terminal=false
Categories=AudioVideo;Video;Player;TV;
StartupNotify=true
StartupWMClass=$wm_class
EOF
desktop-file-validate "$pkg/usr/share/applications/$app_id.desktop"

cp "$src/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
  "$pkg/usr/share/icons/hicolor/192x192/apps/$app_id.png"

find "$pkg" -type d -exec chmod 755 {} +
find "$pkg" -type f -exec chmod 644 {} +
chmod 755 "$opt/tvplayer" "$pkg/usr/bin/tvplayer"

# --- Debian package ---

step "Working out the dependencies"
# libapp.so has no dependencies. libdartjni.so wants libjvm.so, but only the
# Android side of path_provider uses it, so it's never loaded on Linux.
scan=()
for library in "$opt"/lib/*.so; do
  case "$(basename "$library")" in
    libapp.so | libdartjni.so) ;;
    *) scan+=("$library") ;;
  esac
done
mkdir "$work/shlibs" "$work/shlibs/debian"
printf 'Source: tvplayer\n\nPackage: tvplayer\nArchitecture: amd64\n' \
  > "$work/shlibs/debian/control"
shlibs=$(cd "$work/shlibs" && dpkg-shlibdeps -O --ignore-missing-info \
  "-l$opt/lib" "-e$opt/tvplayer" "${scan[@]}" 2>"$work/shlibdeps.log") \
  || { cat "$work/shlibdeps.log" >&2; die "dpkg-shlibdeps failed"; }
shlibs=${shlibs#shlibs:Depends=}
[ -n "$shlibs" ] || die "dpkg-shlibdeps found no dependencies"
depends="$shlibs, $extra_depends"
echo "Depends: $depends"

cat > "$pkg/DEBIAN/control" <<EOF
Package: tvplayer
Version: $full_version
Architecture: amd64
Maintainer: $maintainer
Installed-Size: $(du -sk --exclude=DEBIAN "$pkg" | cut -f1)
Depends: $depends
Section: video
Priority: optional
Homepage: $homepage
Description: IPTV player
 A player for your own IPTV provider. It comes without playlists, providers
 or content.
EOF
chmod 644 "$pkg/DEBIAN/control"

dpkg-deb --root-owner-group --build "$pkg" "$work/$deb_name"

# --- Android ---

step "Building the universal APK"
(cd "$src" && flutter build apk --release)
apk=$work/$apk_name
cp "$src/build/app/outputs/flutter-apk/app-release.apk" "$apk"

listing=$(unzip -Z1 "$apk")
for abi in arm64-v8a armeabi-v7a x86_64; do
  grep -qx "lib/$abi/libapp.so" <<<"$listing" \
    || die "the APK has no app code for $abi, so it isn't universal"
done

step "Verifying the APK signature"
certs=$("$apksigner" verify --print-certs "$apk")
signer_dn=$(sed -n 's/^Signer #1 certificate DN: //p' <<<"$certs")
signer_sha256=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<<"$certs")
[ -n "$signer_dn" ] && [ -n "$signer_sha256" ] || die "no signer found in the APK"
case "$signer_dn" in
  *"CN=Android Debug"*) die "the APK is signed with the Android debug certificate" ;;
esac
signer_cn=$(sed -n 's/.*CN=\([^,]*\).*/\1/p' <<<"$signer_dn")
# The way keytool prints it, to compare by eye.
signer_colons=$(tr a-f A-F <<<"$signer_sha256" | sed 's/../&:/g; s/:$//')

# --- What actually ends up in the files ---

step "Checking the contents for personal data"
mkdir "$work/check" "$work/check/deb" "$work/check/apk"
dpkg-deb -x "$work/$deb_name" "$work/check/deb"
unzip -q "$apk" -d "$work/check/apk"
check=$work/check

bad_names=$(find "$check" \( -name '*.local.*' -o -name '*.jks' -o -name '*.keystore' \
  -o -name 'key.properties' -o -name '.env*' -o -name 'config.local*' \) -print)
[ -z "$bad_names" ] || die "files that must not ship: $bad_names"

while IFS= read -r -d '' elf; do
  runpath=$(readelf -d "$elf" 2>/dev/null | sed -n 's/.*R\(UN\)\{0,1\}PATH.*\[\(.*\)\]/\2/p')
  case "$runpath" in
    *"$work"* | *"$HOME"* | */tmp/* | */home/*)
      die "$(basename "$elf") has a build path as RUNPATH: $runpath" ;;
  esac
done < <(find "$check/deb/opt/tvplayer" -type f \( -name '*.so' -o -name tvplayer \) -print0)

terms=("$HOME" "$USER")
email=$(git config user.email || true)
[ -z "$email" ] || terms+=("$email")
if [ -f "$denylist" ]; then
  while IFS= read -r line; do
    case "$line" in '' | '#'*) ;; *) terms+=("$line") ;; esac
  done < "$denylist"
else
  echo "No $denylist, so your own domains and IPs aren't searched for."
fi
for term in "${terms[@]}"; do
  if hits=$(grep -rlaiF -- "$term" "$check"); then
    # The term stays out of the output: it may be in a pasted log.
    die "term #$(printf '%s\n' "${terms[@]}" | grep -nxF -- "$term" | head -1 | cut -d: -f1) \
of the search list found in: ${hits//$check\//}"
  fi
done
echo "None of the ${#terms[@]} search terms found."

echo
echo "URL hosts and IPs in the app code, to read through:"
for libapp in "$check"/deb/opt/tvplayer/lib/libapp.so "$check"/apk/lib/*/libapp.so; do
  strings -a "$libapp"
done | grep -oE 'https?://[A-Za-z0-9.-]+|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort -u | sed 's/^/  /'

# --- Results ---

rm -rf dist
mkdir dist
cp "$work/$deb_name" "$apk" dist/
(cd dist && sha256sum "$deb_name" "$apk_name" > SHA256SUMS)

step "Done"
cat <<EOF
Version:        $full_version
Commit (short): $commit_short
Commit (full):  $commit
Branch:         $branch
Signer CN:      $signer_cn
Signer SHA-256: $signer_colons

dist/:
$(sed 's/^/  /' dist/SHA256SUMS)

The release tag must point to this commit: git rev-parse v$version^{commit}
EOF
if [ "$branch" != main ]; then
  echo
  echo "WARNING: built from branch $branch, not main. This is for testing only: don't upload it."
fi
