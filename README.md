# arm64 SSL/TLS patch for Haiku

Makes an arm64 Haiku build link its network kit with SSL, so `pkgman` and
anything else using `BUrlRequest` can open an `https://` connection at all.

## The problem

Every arm64 Haiku nightly checked so far -- both the ones this project
builds and the real ones at download.haiku-os.org -- links the `no-ssl`
variant of `libbnetapi.so`: no `libssl`, no `libcrypto`, anywhere in
`pkgman`'s dependency chain (`readelf -d` shows it directly). `pkgman
add-repo https://...` fails outright, not on a bad URL but because there is
no TLS implementation to open the connection with.

`src/kits/network/libnetapi/Jamfile` picks the SSL build only when
`build/jam/BuildFeatures`'s `openssl` feature turns on, which needs two
things at Haiku-build time, not afterward: `openssl3` must be a package the
*image itself* adds (`IsHaikuImagePackageAdded openssl3`, already coded for
the `minimum` profile in `build/jam/DefaultBuildProfiles` -- nothing to
patch there), and `openssl3_devel` must be available in the build
repository (`IsPackageAvailable`). The arm64 bootstrap repository
(`build/jam/repositories/HaikuPorts/arm64`) carries neither, so both checks
fail silently and the whole feature is skipped. Full details, including how
this was confirmed against the real download.haiku-os.org nightly, are in
[rwebpositive-arm64/AGENTS.md](https://github.com/rainygirl/haiku-rwebpositive-arm64/blob/main/AGENTS.md).

## What this fixes, and what it does not

Verified on a rebuild (2026-09-16): `add-ssl-arm64.sh` plus a `jam
@minimum-mmc` rebuild produces a `haiku` package whose `libbnetapi.so` links
`libssl.so.3`/`libcrypto.so.3`, and the finished image carries `openssl3`
without any other change. Booted that image and confirmed the network stack
completes a real TLS handshake and gets a real HTTP response back from both
`eu.hpkg.haiku-os.org` and `raw.githubusercontent.com` -- **this part
works.**

`pkgman add-repo` against either of those still fails, though, with
`*** failed! : Operation not allowed`. That turned out not to be a
networking failure at all: `B_NOT_ALLOWED` is exactly how
`src/kits/package/FetchFileJob.cpp` reports an HTTP 403, 405 or 406 coming
back from the server (confirmed by reading that file, not guessed) -- so the
TLS connection succeeds and a real HTTP conversation happens, and the server
is the one declining it. Ruled out along the way: DNS and IP connectivity
both work fine (`ping`, DHCP), the guest's own user is already `uid=0`, so
it is not a local file-permission problem, and the CA root certificate
bundle being present or missing made no difference (installed it partway
through and the failure was identical either way). What is actually being
rejected, and by which side's header or default, has not been found -- this
needs someone to read Haiku's HTTP client code (or capture the request on
the wire) further than this session did. Until then, `pkgman` over the
network is still not a working install path for WebPositive on arm64; see
[rwebpositive-arm64](https://github.com/rainygirl/haiku-rwebpositive-arm64)'s
own `install-webpositive-arm64.sh` / `inject-webpositive-arm64.sh`, neither
of which needs the guest to reach a network at all.

## Using it

Needs a Haiku arm64 source tree that has already been built once (so
`generated.arm64/download/` and the cross toolchain exist), and
`openssl3`/`openssl3_devel` arm64 `.hpkg` files -- `packages/` here ships
copies of the ones this project already cross-compiled for HaikuWebKit.

```sh
curl -fsSL https://raw.githubusercontent.com/rainygirl/haiku-renku-arm64-ssltlspatch/main/add-ssl-arm64.sh \
	-o add-ssl-arm64.sh
curl -fsSL https://raw.githubusercontent.com/rainygirl/haiku-renku-arm64-ssltlspatch/main/packages/openssl3-3.5.4-1-arm64.hpkg \
	-o openssl3-3.5.4-1-arm64.hpkg
curl -fsSL https://raw.githubusercontent.com/rainygirl/haiku-renku-arm64-ssltlspatch/main/packages/openssl3_devel-3.5.4-1-arm64.hpkg \
	-o openssl3_devel-3.5.4-1-arm64.hpkg
mkdir -p packages
mv openssl3-3.5.4-1-arm64.hpkg openssl3_devel-3.5.4-1-arm64.hpkg packages/

sh add-ssl-arm64.sh /path/to/haiku /path/to/generated.arm64

export HAIKU_NO_DOWNLOADS=1
cd /path/to/generated.arm64 && jam -q -j$(nproc) @minimum-mmc
```

Or, already on a machine with this repository checked out as a sibling of
the Haiku tree:

```sh
curl -fsSL https://raw.githubusercontent.com/rainygirl/haiku-renku-arm64-ssltlspatch/main/add-ssl-arm64.sh | \
	bash -s -- /path/to/haiku /path/to/generated.arm64
```

(That second form only fetches the script itself; it still needs
`OPENSSL_PKG`/`OPENSSL_DEVEL_PKG` pointed at real files, since a pipe to
`bash` has no `packages/` directory of its own next to it -- set both as
environment variables before the `curl | bash` if you are not running from
a checkout of this repository.)

This program was written with Claude.
