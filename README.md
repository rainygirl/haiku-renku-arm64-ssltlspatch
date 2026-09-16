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

## What this fixes -- all of it, as of the follow-up session

Verified on a rebuild (2026-09-16): `add-ssl-arm64.sh` plus a `jam
@minimum-mmc` rebuild produces a `haiku` package whose `libbnetapi.so` links
`libssl.so.3`/`libcrypto.so.3`, and the finished image carries `openssl3`
without any other change.

The first attempt at using it stalled on `pkgman add-repo` failing against
every host tried -- `eu.hpkg.haiku-os.org`, `raw.githubusercontent.com`,
plain `http://` -- with `*** failed! : Operation not allowed`, and a wrong
turn chasing a server-side 403/405/406 theory (`B_NOT_ALLOWED` really is
what `src/kits/package/FetchFileJob.cpp` returns for those, but a raw
request replay via `curl` with Haiku's exact headers never reproduced the
failure). The real cause, found by patching `SecureSocket.cpp`'s silently-
swallowed `SSL_ERROR_SSL` case to print the underlying OpenSSL error before
returning: `error:0A000086:SSL routines::certificate verify failed`. Not a
network problem, not a missing trust store -- `openssl s_client -CAfile
CARootCertificates.pem` against the same host gave `Verify return code: 9
(certificate is not yet valid)`, and the guest's own `date` read
`Thu Jan 1 00:04:30 GMT 1970`. The QEMU `virt` board's RTC is never read
at boot, so every arm64 guest here starts at the Unix epoch, and no real
certificate is valid yet by that clock. Setting the date by hand
(`date MMDDhhmmYYYY`) made the exact same `add-repo` call succeed
immediately.

**So: this build patch is necessary but not sufficient on its own.**
Anyone using it also needs the guest's clock set correctly before `pkgman`
can reach anything over https -- check with `date`, fix it if it reads
1970. With that done, `pkgman add-repo` and `pkgman install` both work
completely; see
[rwebpositive-arm64](https://github.com/rainygirl/haiku-rwebpositive-arm64)'s
README for the exact commands (and two more small, since-fixed snags on the
repository side: a `repo.sha256` file next to the index, and every
package's filename matching its own embedded version string exactly).

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
