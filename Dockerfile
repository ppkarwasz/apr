# Build environment for APR and its Debian package (debian:sid).
#
# Build the image once (UID/GID make files written to mounted
# directories belong to you):
#
#   docker build -t apr-build --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
#
# Out-of-tree upstream build with SBOMs, from this directory (apr/ must
# not be configured in place):
#
#   mkdir -p out
#   docker run --rm -v "$PWD/apr":/src:ro -v "$PWD/out":/out apr-build sh -ec '
#       cp -a /src /tmp/apr && cd /tmp/apr && ./buildconf
#       chmod -R a-w /tmp/apr
#       mkdir /tmp/build && cd /tmp/build && /tmp/apr/configure
#       make -j"$(nproc)" && make sbom source-sbom
#       cp apr.cdx.json apr-source.cdx.json /out/'
#
# Debian package build (the .deb files are written next to apr-debian/):
#
#   docker run --rm -v "$PWD":/work -w /work/apr-debian \
#       -e DEB_BUILD_OPTIONS=nocheck apr-build dpkg-buildpackage -us -uc -b
#
# Rebuild the image (with --pull) to pick up updates of sid, or after
# Build-Depends in apr-debian/debian/control change.

FROM debian:sid

ARG DEBIAN_FRONTEND=noninteractive

# Tools for building APR from a checkout, building Debian packages and
# checking the results.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential autoconf libtool libtool-bin python3 \
      uuid-dev libcrypt-dev jq pkgconf \
      devscripts equivs fakeroot lintian reuse \
 && rm -rf /var/lib/apt/lists/*

# Build dependencies of the Debian package, taken from its control file.
COPY apr-debian/debian/control /tmp/control
RUN apt-get update \
 && cd /tmp \
 && mk-build-deps -i -r -t "apt-get -y --no-install-recommends" /tmp/control \
 && rm -rf /tmp/control /var/lib/apt/lists/*

# Unprivileged user matching the owner of the mounted directories.
ARG UID=1000
ARG GID=1000
RUN groupadd -o -g "$GID" builder \
 && useradd -o -m -u "$UID" -g "$GID" builder
USER builder
WORKDIR /home/builder
