# SBOMs from upstream to packages: an APR experiment

This fork of the [Apache Portable Runtime](https://apr.apache.org/) (APR) explores how an upstream project and the
distributions packaging it can produce and share Software Bills of Materials (SBOMs).

The idea is that the SBOM is written once, where the knowledge is:

- **Upstream** knows what is in its sources (third-party code, licenses, copyrights) and which libraries a build links
  against.
  APR's build system generates [CycloneDX 1.7](https://cyclonedx.org/) SBOMs from that knowledge.
- **Packagers** know which packages provide those libraries in their distribution, and which patches they apply.
  Instead of producing an SBOM from scratch, they take the upstream build SBOM and *bind* it to their packages.

For now only Debian is implemented.

This is an experiment, not an official Apache APR or Debian release.

## Branches

| Branch                                                                         | Content                                                                                                                                                                                                 |
|--------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `sbom-demo`                                                                    | This README and a Dockerfile for the build environment.                                                                                                                                                 |
| [`asf/sbom-1.7.x`](https://github.com/ppkarwasz/apr/tree/asf/sbom-1.7.x)       | APR 1.7.x with REUSE compliance and SBOM generation (upstream side).                                                                                                                                    |
| [`debian/sbom-1.7.x`](https://github.com/ppkarwasz/apr/tree/debian/sbom-1.7.x) | The Debian packaging of APR (from [salsa.debian.org/apache-team/apr](https://salsa.debian.org/apache-team/apr)), building `asf/sbom-1.7.x` and shipping an SBOM in each binary package (packager side). |

`asf/sbom-1.7.x` adds three commits to APR's 1.7.x branch:

1. **REUSE compliance**: copyright and licensing information for every file, following
   the [REUSE specification](https://reuse.software/).
   Third-party code carries `SPDX-License-Identifier` and `SPDX-FileCopyrightText` tags next to its original notice, or
   `SPDX-SnippetBegin`/`SPDX-SnippetEnd` tags around the parts of a file it occupies;
   `REUSE.toml` covers everything else, and `LICENSES/` holds the license texts.
2. A `.gitignore`, backported from APR 1.8.x.
3. **SBOM generation**: `make source-sbom` and `make sbom`, implemented by `build/sbom.sh` (POSIX shell
   and [jq](https://jqlang.org/)) with the data in `build/sbom/components.json`.

`debian/sbom-1.7.x` merges `asf/sbom-1.7.x` directly, so its history contains the upstream commits.

## How it works

```
 APR source tree ───── make source-sbom ────▶ apr-source.cdx.json        lifecycle: pre-build
       │
   configure, make ─── make sbom ───────────▶ apr.cdx.json              lifecycle: build
                                                    │
 Debian package build                               │ debian/sbom-bind.sh,
 (dpkg-buildpackage)                                │ after dh_shlibdeps
                                                    ▼
                         /usr/share/doc/libapr1t64/libapr1t64.cdx.json    lifecycle: build
                         /usr/share/doc/libapr1-dev/libapr1-dev.cdx.json
```

### Upstream: the source SBOM

`make source-sbom` describes the source tree, mostly for license compliance:

- every piece of third-party code in APR, with its license and copyright read from the SPDX tags, and the files (or line
  ranges, for snippets) where it occurs;
- the build tools copied into the tree (GNU config, an Autoconf Archive macro, and in release tarballs the libtool files
  and `configure`);
- every library the UNIX build may link against, as an external component (`isExternal: true`) with the range of
  versions accepted (`versionRange`).

The generator checks the source tree against `build/sbom/components.json`:
it fails if a file carries a license tag other than Apache-2.0 that no component accounts for, so newly added
third-party code cannot go unnoticed.

### Upstream: the build SBOM

`make sbom` describes one build of `libapr`:

- the libraries it needs at run time, read from the `DT_NEEDED` entries of the built shared library, with the versions
  found on the build system and the files they resolved to (e.g. `/usr/lib/x86_64-linux-gnu/libuuid.so.1`);
- the third-party code compiled in, but only code from a **maintained** upstream whose advisories could apply.
  Code forked from 4.4BSD or UNIX V7 decades ago is marked `historical` in `components.json`: it matters for license
  compliance, so it stays in the source SBOM, but would only add noise to vulnerability matching.

### Packager: binding the build SBOM to Debian packages

`debian/sbom-bind.sh` runs during the package build, after `dh_shlibdeps`, and derives the SBOM of each binary package
from the upstream build SBOM:

- `metadata.component` becomes the Debian package (`pkg:deb/debian/libapr1t64@…`);
  the upstream component becomes its pedigree ancestor, and `debian/patches` its patches;
- each external library is bound to the Debian package owning the file it resolved to (`dpkg -S`), with the version
  range taken from `shlibs:Depends` (e.g. `libc6`, `vers:deb/>=2.38`);
- the bundled code is copied unchanged.

The result is shipped in `/usr/share/doc/<package>/<package>.cdx.json`.

### Reproducibility

The SBOMs are reproducible:
the timestamp comes from `SOURCE_DATE_EPOCH`, the serial number is a version 5 UUID derived from the package URL, the
scripts run with `LC_ALL=C`, and build paths are recorded as `@abs_builddir@` and `@abs_srcdir@`.

## Try it

You need git and Docker.

Clone this fork and check out the two code branches as worktrees next to this README:

```sh
git clone -b sbom-demo https://github.com/ppkarwasz/apr.git apr-sbom
cd apr-sbom
git worktree add apr asf/sbom-1.7.x
git worktree add apr-debian debian/sbom-1.7.x
```

Build the image with the build environment (Debian sid with APR's build dependencies, jq, lintian and reuse).
`UID` and `GID` make the files written by the containers yours:

```sh
docker build -t apr-build --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
```

### Upstream SBOMs

Build APR outside its source tree and generate both SBOMs into `out/`:

```sh
mkdir -p out
docker run --rm -v "$PWD/apr":/src:ro -v "$PWD/out":/out apr-build sh -ec '
    cp -a /src /tmp/apr && cd /tmp/apr && ./buildconf
    chmod -R a-w /tmp/apr
    mkdir /tmp/build && cd /tmp/build && /tmp/apr/configure
    make -j"$(nproc)" && make sbom source-sbom
    cp apr.cdx.json apr-source.cdx.json /out/'
```

The source tree is mounted read-only and the copy is write-protected after `buildconf`, which also checks that the build
does not write into the sources.

### Debian packages

```sh
docker run --rm -v "$PWD":/work -w /work/apr-debian -e DEB_BUILD_OPTIONS=nocheck \
    apr-build dpkg-buildpackage -us -uc -b
```

The packages are written to this directory.
Extract an SBOM with:

```sh
dpkg-deb --fsys-tarfile libapr1t64_*.deb \
    | tar -xO ./usr/share/doc/libapr1t64/libapr1t64.cdx.json | jq .
```

Clean the Debian tree afterwards with:

```sh
docker run --rm -v "$PWD":/work -w /work/apr-debian apr-build fakeroot debian/rules clean
```

### Checks

```sh
docker run --rm -v "$PWD/apr":/src -w /src apr-build reuse lint
docker run --rm -v "$PWD":/work -w /work apr-build lintian -I *.changes
```

The SBOMs can be validated against the CycloneDX 1.7 schema, for example
with [CycloneDX CLI](https://github.com/CycloneDX/cyclonedx-cli):
`cyclonedx validate --input-file apr.cdx.json --input-version v1_7`.

## Status and open questions

- Only the UNIX build of APR and only Debian packaging are covered.
- Release tarballs contain files generated by `buildconf` (`configure`, libtool's files), whose license texts are not in
  `LICENSES/`:
  REUSE rejects unused licenses in the git tree, so the release process would have to add them.
- The upstream version ranges are `vers:generic/*`, because APR's configure script checks no minimum versions.
- Debian has no convention yet for where a package ships its SBOM.
- Should SBOMs embed the full text of the distribution patches, or only reference them?
- On APR 1.8.x, the vendored [cryptoint](https://lib.mceliece.org/) code is the only third-party code with a maintained
  upstream; it has no package URL or CPE to match advisories against.

## License

The content of this branch is licensed under the Apache License, Version 2.0, like APR itself.
