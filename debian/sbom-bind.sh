#!/bin/sh
#
# sbom-bind.sh -- derive the CycloneDX SBOM of a Debian binary package
#                 from APR's upstream build SBOM
#
# Usage:
#   debian/sbom-bind.sh --build-sbom FILE [--package PACKAGE]
#                       [--installed-as LIST] [--substvars FILE]
#                       [--patches DIR] [--version VERSION]
#                       [--arch ARCH] [--distro CODENAME]
#
#   Run from the top of the source package.  FILE is the SBOM written by
#   "make sbom" (apr.cdx.json).  The output, on stdout, describes PACKAGE:
#
#   - metadata.component is the Debian package; the upstream component
#     becomes its pedigree ancestor and debian/patches its patches;
#   - bundled components are copied unchanged when their apr:installed-as
#     property is in LIST (comma-separated);
#   - external components (only with "library" in LIST) are bound to the
#     Debian packages owning the files they resolved to at build time,
#     with the version range from shlibs:Depends in the substvars FILE
#     (default debian/PACKAGE.substvars, written by dh_shlibdeps).
#
#   PACKAGE must be one of the packages this source builds (as listed by
#   dh_listpackages).  It defaults to the shared library package, the one
#   whose Depends contains ${shlibs:Depends}.  LIST defaults to "library"
#   for that package and to "header,build-file" for a -dev package.
#
#   VERSION and ARCH default to the changelog version and DEB_HOST_ARCH.
#   CODENAME defaults to the distribution the changelog targets (that of
#   the previous entry while UNRELEASED; unstable is sid).  External
#   components are bound using the packages installed on this system, so
#   the system must be the targeted distribution, e.g. the chroot the
#   package is built in; passing --distro skips this check.
#
# Environment:
#   SOURCE_DATE_EPOCH  If set (dpkg-buildpackage sets it), used as the
#                      timestamp and for the serial number.
#   JQ                 jq program (default: jq).

set -e
LC_ALL=C
export LC_ALL

usage() {
    sed -n '/^# Usage:/,/^# Environment:/p' "$0" | sed '$d' \
        | sed 's/^# \{0,1\}//' >&2
    exit 1
}

die() {
    echo "$0: $*" >&2
    exit 1
}

warn() {
    echo "$0: warning: $*" >&2
}

build_sbom=
package=
installed_as=
substvars=
patches=debian/patches
version=
arch=
distro=

while test $# -gt 0; do
    test $# -ge 2 || usage
    case $1 in
      --build-sbom)   build_sbom=$2 ;;
      --package)      package=$2 ;;
      --installed-as) installed_as=$2 ;;
      --substvars)    substvars=$2 ;;
      --patches)      patches=$2 ;;
      --version)      version=$2 ;;
      --arch)         arch=$2 ;;
      --distro)       distro=$2 ;;
      *)              usage ;;
    esac
    shift 2
done
test -n "$build_sbom" || usage
test -f "$build_sbom" || die "$build_sbom not found"
test -f debian/control || die "run from the top of the source package"

JQ=${JQ:-jq}
vendor=`dpkg-vendor --query Vendor 2>/dev/null || echo Debian`
namespace=`echo "$vendor" | tr 'A-Z' 'a-z'`

# ---------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------

# The binary packages this source builds for the host architecture.
list_packages() {
    dh_listpackages 2>/dev/null || sed -n 's/^Package: *//p' debian/control
}

# The packages whose Depends contain ${shlibs:Depends}, i.e. that ship
# shared libraries.
shlib_packages() {
    awk '/^$/           { field = "" }
         /^[^ \t]/      { field = $1 }
         /^Package:/    { pkg = $2 }
         field == "Depends:" && /\$\{shlibs:Depends\}/ { print pkg }' \
        debian/control | sort -u
}

packages=`list_packages`
test -n "$packages" || die "no binary packages found in debian/control"
shlibs=`shlib_packages`

if test -z "$package"; then
    for p in $shlibs; do
        case " `echo $packages` " in
          *" $p "*) package="$package $p" ;;
        esac
    done
    set -- $package
    test $# -eq 1 \
        || die "cannot tell the shared library package (candidates:${package:- none}); use --package"
    package=$1
else
    case " `echo $packages` " in
      *" $package "*) ;;
      *) die "$package is not built by this source package (it builds: `echo $packages`)" ;;
    esac
fi

if test -z "$installed_as"; then
    case " `echo $shlibs` " in
      *" $package "*) installed_as=library ;;
      *)
        case $package in
          *-dev) installed_as=header,build-file ;;
          *) die "use --installed-as to say what $package contains" ;;
        esac
        ;;
    esac
fi

substvars=${substvars:-debian/$package.substvars}
test -n "$version" || version=`dpkg-parsechangelog -SVersion`
test -n "$arch" || arch=`dpkg-architecture -qDEB_HOST_ARCH`

# ---------------------------------------------------------------------
# Distribution
# ---------------------------------------------------------------------

# The codename the changelog targets: the previous entry's distribution
# while this one is UNRELEASED, without suite suffixes such as -security;
# Debian's unstable and experimental are sid.
target_distro() {
    _d=`dpkg-parsechangelog -SDistribution`
    if test "$_d" = UNRELEASED; then
        _d=`dpkg-parsechangelog -o1 -c1 -SDistribution 2>/dev/null || true`
    fi
    set -- $_d
    _d=$1
    _d=`echo "$_d" | sed -e 's/-security$//' -e 's/-backports-sloppy$//' \
                         -e 's/-backports$//' -e 's/-proposed-updates$//' \
                         -e 's/-updates$//'`
    if test "$namespace" = debian; then
        case $_d in
          unstable|experimental) _d=sid ;;
        esac
    fi
    test "$_d" != UNRELEASED || _d=
    echo "$_d"
}

# Is this system distribution $1?  Debian testing and unstable both
# report "CODENAME/sid" in /etc/debian_version, so that matches either.
host_is() {
    _dv=`cat /etc/debian_version 2>/dev/null || true`
    case $_dv in
      */sid)
        test "$1" = sid || test "$1" = "${_dv%/sid}"
        return
        ;;
    esac
    test "$1" = "`. /etc/os-release && echo "$VERSION_CODENAME"`"
}

if test -z "$distro"; then
    distro=`target_distro`
    test -n "$distro" \
        || die "cannot tell the target distribution from debian/changelog; use --distro"
    if ! host_is "$distro"; then
        _host=`. /etc/os-release && echo "$PRETTY_NAME"`
        die "$package targets $distro, but this system is $_host;" \
            "the libraries would be bound to its packages, not to those of $distro." \
            "Run in a $distro build environment, or pass --distro to override."
    fi
fi

# PURL of a Debian package: purl NAME ARCH [VERSION]
purl() {
    $JQ -nr --arg ns "$namespace" --arg n "$1" --arg a "$2" --arg v "$3" \
        --arg d "$distro" '
        "pkg:deb/\($ns)/\($n)"
        + (if $v == "" then "" else "@" + ($v | @uri) end)
        + "?arch=\($a)" + (if $d == "" then "" else "&distro=\($d)" end)'
}

# ---------------------------------------------------------------------
# Binding external components to packages
# ---------------------------------------------------------------------

# Print "PACKAGE ARCH" of the package owning file $1.  dpkg knows files
# by the paths packages ship, which may differ from the merged-/usr path
# the compiler reported, so the /lib <-> /usr/lib alias is tried too.
owner() {
    for _p in "$1" `echo "$1" | sed -n 's|^/usr/lib/|/lib/|p'` \
              `echo "$1" | sed -n 's|^/lib/|/usr/lib/|p'`; do
        _o=`dpkg -S "$_p" 2>/dev/null \
            | sed -n 's/^\([^,:]*\)\(:\([^,:]*\)\)\{0,1\}: .*$/\1 \3/p' | sed q \
            | awk '{ print $1, ($2 == "" ? "-" : $2) }'`
        if test -n "$_o"; then
            echo "$_o"
            return 0
        fi
    done
}

# The vers range package $1 is required in by shlibs:Depends, or "*".
version_range() {
    _deps=`sed -n 's/^shlibs:Depends=//p' "$substvars" 2>/dev/null`
    printf '%s\n' "$_deps" | tr ',' '\n' | sed 's/^ *//' | grep -v '|' \
        | sed -n "s/^$1 *(\([<>=]*\) *\([^)]*\))\$/\1 \2/p;s/^$1\$/*/p" | sed q \
        | sed -e 's/^>> /> /' -e 's/^<< /< /' -e 's/^>= />=/' -e 's/^<= /<=/' \
              -e 's/^= /=/' -e 's/^> />/' -e 's/^< /</'
}

# One line per external component: its bound form, as JSON.
bind_externals() {
    $JQ -c '.components[] | select(.isExternal == true)' "$build_sbom" \
    | while read -r comp; do
        ref=`printf '%s' "$comp" | $JQ -r '."bom-ref"'`
        pkgs=
        for path in `printf '%s' "$comp" | $JQ -r '.evidence.occurrences[]?.location'`; do
            o=`owner "$path"`
            if test -z "$o"; then
                warn "$ref: no package owns $path"
                continue
            fi
            case " $pkgs " in
              *" $o "*) ;;
              *) pkgs="$pkgs $o" ;;
            esac
        done
        if test -z "$pkgs"; then
            warn "$ref: not bound to a package"
            printf '%s\n' "$comp"
            continue
        fi
        set -- $pkgs
        multi=false
        test $# -le 2 || multi=true
        while test $# -ge 2; do
            pkg=$1 parch=$2
            shift 2
            test "$parch" != - || parch=$arch
            range=`version_range "$pkg"`
            test -n "$range" || range='*'
            pver=`dpkg-query -W -f='${Version}' "$pkg:$parch" 2>/dev/null \
                  || dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true`
            src=`dpkg-query -W -f='${source:Package}' "$pkg:$parch" 2>/dev/null \
                 || dpkg-query -W -f='${source:Package}' "$pkg" 2>/dev/null || true`
            printf '%s' "$comp" | $JQ -c \
                --arg pkg "$pkg" --arg purl "`purl "$pkg" "$parch"`" \
                --arg range "vers:deb/$range" --arg pver "$pver" --arg src "$src" \
                --arg vendor "$vendor" --argjson multi "$multi" '
                { type: "library",
                  "bom-ref": (if $multi then ."bom-ref" + ":" + $pkg else ."bom-ref" end),
                  supplier: { name: $vendor },
                  name: $pkg,
                  versionRange: $range,
                  isExternal: true,
                  description: .description,
                  scope: "required",
                  purl: $purl,
                  properties: ((.properties // [])
                    + [ { name: "debian:build-version", value: $pver },
                        { name: "debian:source-package", value: $src },
                        { name: "apr:upstream-name", value: .name } ]
                    + (if .version then [ { name: "apr:upstream-version", value: .version } ]
                       else [] end)
                    | map(select(.value != ""))),
                  evidence: .evidence }'
        done
    done
}

# ---------------------------------------------------------------------
# Patches
# ---------------------------------------------------------------------

# One JSON patch object per line, from the quilt series in $patches.
debian_patches() {
    test -f "$patches/series" || return 0
    sed -e 's/#.*//' -e 's/[ 	].*//' -e '/^$/d' "$patches/series" \
    | while read -r p; do
        test -f "$patches/$p" || die "$patches/$p listed in series but missing"
        origin=`sed -n 's/^Origin: *\([A-Za-z-]*\).*/\1/p' "$patches/$p" | sed q`
        case $origin in
          upstream|backport) type=backport ;;
          *)                 type=unofficial ;;
        esac
        $JQ -c -R -s --arg type "$type" --arg name "debian/patches/$p" '
            { type: $type,
              diff: { text: { contentType: "text/x-diff", content: . },
                      url: $name } }' < "$patches/$p"
    done
}

# ---------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------

want_externals=no
case ",$installed_as," in
  *,library,*) want_externals=yes ;;
esac

externals=
if test $want_externals = yes; then
    test -f "$substvars" || warn "$substvars not found; version ranges will be *"
    externals=`bind_externals`
fi
# The patches embed their full text, which can exceed the size limit of
# a command line argument, so they are passed to jq in a file.
patches_file=`mktemp`
trap 'rm -f "$patches_file"' EXIT
debian_patches > "$patches_file"
pkg_purl=`purl "$package" "$arch" "$version"`

# Assemble the package SBOM from the bound externals on stdin.
assemble() {
    $JQ -s \
    --slurpfile build "$build_sbom" \
    --arg package "$package" --arg version "$version" --arg purl "$pkg_purl" \
    --arg vendor "$vendor" --arg installed "$installed_as" \
    --arg epoch "${SOURCE_DATE_EPOCH:-}" \
    --slurpfile patches "$patches_file" '
    . as $externals
    | $build[0] as $b
    | ($installed | split(",")) as $want
    | [ $b.components[]
        | select(.isExternal != true)
        | select(any(.properties[]?; .name == "apr:installed-as"
                                     and (.value as $v | any($want[]; . == $v)))) ]
      as $bundled
    | { "$schema": $b."$schema",
        bomFormat: "CycloneDX",
        specVersion: $b.specVersion,
        version: 1,
        metadata: (
          (if $epoch == "" then {}
           else { timestamp: ($epoch | tonumber | floor | todate) } end)
          + {
            lifecycles: [ { phase: "post-build" } ],
            tools: {
              components: ($b.metadata.tools.components
                + [ { type: "application", name: "debian/sbom-bind.sh",
                      version: $version } ]) },
            component: {
              type: "library",
              "bom-ref": $package,
              supplier: { name: $vendor },
              name: $package,
              version: $version,
              description: $b.metadata.component.description,
              licenses: $b.metadata.component.licenses,
              purl: $purl,
              pedigree: (
                { ancestors: [ $b.metadata.component ] }
                + (if ($patches | length) > 0 then { patches: $patches }
                   else {} end)) } }),
        components: ($bundled + $externals),
        dependencies: [
          { ref: $package,
            dependsOn: [ ($bundled + $externals)[]
                         | select(.scope != "excluded") | ."bom-ref" ] } ] }'
}

bom=`printf '%s\n' "$externals" | sed '/^$/d' | assemble`

# serialNumber: version 5 UUID (URL namespace) of
# PURL#sbom=post-build[&source_date_epoch=EPOCH][&sha256=DIGEST], the
# digest being added only when SOURCE_DATE_EPOCH is unset.

hexdigest() {
    if (sha${1}sum </dev/null) >/dev/null 2>&1; then
        sha${1}sum | sed 's/ .*//'
    elif (openssl dgst -sha$1 </dev/null) >/dev/null 2>&1; then
        openssl dgst -sha$1 | sed 's/^.* //'
    fi
}

NS_URL='\153\247\270\021\235\255\021\321\200\264\000\300\117\324\060\310'

uuid5() {
    _h=`{ printf "$NS_URL"; printf '%s' "$1"; } | hexdigest 1`
    test -n "$_h" || return 0
    case `echo "$_h" | cut -c17` in
      0|4|8|c) _v=8 ;;
      1|5|9|d) _v=9 ;;
      2|6|a|e) _v=a ;;
      *)       _v=b ;;
    esac
    echo "$_h" | sed "s/^\(........\)\(....\).\(...\).\(...\)\(............\).*/\1-\2-5\3-$_v\4-\5/"
}

name="$pkg_purl#sbom=post-build"
if test -n "$SOURCE_DATE_EPOCH"; then
    name="$name&source_date_epoch=$SOURCE_DATE_EPOCH"
else
    name="$name&sha256=`printf '%s\n' "$bom" | hexdigest 256`"
fi
serial=`uuid5 "$name"`

printf '%s\n' "$bom" | $JQ --arg serial "$serial" '
    if $serial == "" then .
    else
      { "$schema": ."$schema", bomFormat: .bomFormat, specVersion: .specVersion,
        serialNumber: ("urn:uuid:" + $serial) }
      + .
    end'
