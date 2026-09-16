#!/bin/sh
#
# Make an arm64 Haiku build link its network kit with SSL, so pkgman and
# anything else using BUrlRequest can reach an https:// URL.
#
# The arm64 bootstrap repository (build/jam/repositories/HaikuPorts/arm64)
# carries no OpenSSL package, so every arm64 "haiku" built from it links the
# no-ssl variant of libbnetapi.so: no libssl, no libcrypto, anywhere in
# pkgman's dependency chain. Every arm64 nightly checked so far, including
# the real ones at download.haiku-os.org, is built this way. See
# ../rwebpositive-arm64/AGENTS.md, "pkgman over the network: arm64 has no
# TLS at all", for how that was confirmed.
#
# src/kits/network/libnetapi/Jamfile decides ssl vs no-ssl from a build
# feature (HAIKU_BUILD_FEATURE_SSL), which build/jam/BuildFeatures turns on
# only once openssl3 is a package the image actually adds
# (IsHaikuImagePackageAdded) *and* openssl3_devel is available in the build
# repository (IsPackageAvailable) to get headers and import libraries from.
# build/jam/DefaultBuildProfiles already does
# `AddHaikuImageSystemPackages openssl3` for the "minimum" profile -- it is
# only ever skipped because the package it names does not exist in the
# arm64 repository. So the fix is entirely in what packages that repository
# offers, no Jamfile changes needed.
#
#   ./add-ssl-arm64.sh <path-to-haiku-tree> <path-to-generated.arm64>
#
# Needs openssl3-*.hpkg and openssl3_devel-*.hpkg for arm64 next to this
# script (or pass OPENSSL_PKG / OPENSSL_DEVEL_PKG). rwebpositive-arm64
# already built a pair while cross-compiling HaikuWebKit; the ones this
# script ships are copies of exactly those.
#
# Run this, then rebuild the image (jam -q @minimum-anyboot or whichever
# profile) with HAIKU_NO_DOWNLOADS=1 still set, same as any other build
# after the repository file changes -- see rwebpositive-arm64/AGENTS.md for
# why that variable has to be set in jam's own environment, not
# UserBuildConfig.
#
set -eu

HAIKU_TREE="${1:?usage: add-ssl-arm64.sh <path-to-haiku-tree> <path-to-generated.arm64>}"
GENERATED="${2:?usage: add-ssl-arm64.sh <path-to-haiku-tree> <path-to-generated.arm64>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

OPENSSL_PKG="${OPENSSL_PKG:-$HERE/packages/openssl3-3.5.4-1-arm64.hpkg}"
OPENSSL_DEVEL_PKG="${OPENSSL_DEVEL_PKG:-$HERE/packages/openssl3_devel-3.5.4-1-arm64.hpkg}"

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

REPO_FILE="$HAIKU_TREE/build/jam/repositories/HaikuPorts/arm64"
DOWNLOAD_DIR="$GENERATED/download"

[ -f "$REPO_FILE" ] || die "no repository file at $REPO_FILE -- wrong tree?"
[ -d "$DOWNLOAD_DIR" ] || die "no download directory at $DOWNLOAD_DIR -- build once first"
[ -f "$OPENSSL_PKG" ] || die "missing $OPENSSL_PKG"
[ -f "$OPENSSL_DEVEL_PKG" ] || die "missing $OPENSSL_DEVEL_PKG"

# ---------------------------------------------------------------------------
step "Checking the current state"

if grep -q '^	openssl3-' "$REPO_FILE"; then
	say "openssl3 is already in $REPO_FILE"
else
	say "openssl3 is not in the repository yet -- adding it"
fi

# ---------------------------------------------------------------------------
step "Patching the arm64 repository definition"

if ! grep -q '^	openssl3-' "$REPO_FILE"; then
	# Insert right after the "primary architecture (arm64)" comment, in the
	# same style as every other bootstrap entry (name-version-revision, no
	# architecture suffix -- that is implied by the section).
	awk '
		{ print }
		/# primary architecture \(arm64\)/ && !done {
			print "\topenssl3-3.5.4-1"
			print "\topenssl3_devel-3.5.4-1"
			done = 1
		}
	' "$REPO_FILE" > "$REPO_FILE.new"
	mv "$REPO_FILE.new" "$REPO_FILE"
	say "added openssl3-3.5.4-1 and openssl3_devel-3.5.4-1"
else
	say "nothing to patch"
fi

# ---------------------------------------------------------------------------
step "Staging the packages"

for f in "$OPENSSL_PKG" "$OPENSSL_DEVEL_PKG"; do
	dest="$DOWNLOAD_DIR/$(basename "$f")"
	if [ -e "$dest" ]; then
		say "already staged  $(basename "$f")"
	else
		cp "$f" "$dest"
		say "staged          $(basename "$f")"
	fi
done

say ""
say "Done. Rebuild with HAIKU_NO_DOWNLOADS=1 exported (changing the"
say "repository file changes its checksum, and jam will otherwise try to"
say "fetch a matching index from the network):"
say ""
say "    export HAIKU_NO_DOWNLOADS=1"
say "    cd $GENERATED && jam -q -j\$(nproc) @minimum-mmc"
say ""
say "Check the result before trusting it -- extract lib/libbnetapi.so from"
say "the built haiku-*.hpkg and look for libssl.so.3/libcrypto.so.3 in its"
say "NEEDED entries (readelf -d), and confirm openssl3-*.hpkg is one of the"
say "packages the finished image actually carries."
