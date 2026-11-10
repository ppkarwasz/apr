#!/bin/sh
#
# apr-sbom-bind.sh -- derive the CycloneDX SBOM of a Fedora binary package
#                     from APR's upstream build SBOM
#
# Usage:
#   apr-sbom-bind.sh --build-sbom FILE --package NAME --version EVR
#                    --arch ARCH --distro DISTRO [--installed-as LIST]
#                    [--source-sbom FILE --add-source-component REF]...
#                    [-- PATCH...]
#
#   FILE is the SBOM written by "make sbom" (apr.cdx.json).  The output,
#   on stdout, describes the binary package NAME, version EVR
#   ([EPOCH:]VERSION-RELEASE), built for ARCH on DISTRO (e.g. fedora-45):
#
#   - metadata.component is the package; the upstream component becomes
#     its pedigree ancestor and the PATCH files its patches;
#   - bundled components are copied unchanged when their apr:installed-as
#     property is in LIST (comma-separated, default "library");
#   - external components (only with "library" in LIST) are bound to the
#     RPM packages owning the files they resolved to at build time, with
#     the exact version built against;
#   - --add-source-component copies a component of the upstream source
#     SBOM (apr-source.cdx.json), for upstream files the package ships
#     that the build SBOM does not list, e.g. build helpers.
#
#   Run it in the build environment, e.g. from the %install section of
#   the spec file: external components are bound using the packages
#   installed there.
#
# Environment:
#   SOURCE_DATE_EPOCH  If set (rpmbuild sets it from the changelog), used
#                      as the timestamp and for the serial number.
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
source_sbom=
package=
version=
arch=
distro=
installed_as=library
add_components=

while test $# -gt 0; do
    case $1 in
      --) shift; break ;;
    esac
    test $# -ge 2 || usage
    case $1 in
      --build-sbom)           build_sbom=$2 ;;
      --source-sbom)          source_sbom=$2 ;;
      --package)              package=$2 ;;
      --version)              version=$2 ;;
      --arch)                 arch=$2 ;;
      --distro)               distro=$2 ;;
      --installed-as)         installed_as=$2 ;;
      --add-source-component) add_components="$add_components $2" ;;
      *)                      usage ;;
    esac
    shift 2
done
# The remaining arguments are the patches applied to the upstream source.

test -n "$build_sbom" && test -n "$package" && test -n "$version" \
    && test -n "$arch" && test -n "$distro" || usage
test -f "$build_sbom" || die "$build_sbom not found"
if test -n "$add_components"; then
    test -f "$source_sbom" || die "--add-source-component needs --source-sbom"
fi

JQ=${JQ:-jq}
vendor="Fedora Project"
namespace=fedora

# EVR without the epoch, and the epoch alone.
case $version in
  *:*) epoch=${version%%:*} vr=${version#*:} ;;
  *)   epoch= vr=$version ;;
esac

# PURL of an RPM package: purl NAME ARCH [VERSION-RELEASE [EPOCH]]
purl() {
    $JQ -nr --arg ns "$namespace" --arg n "$1" --arg a "$2" --arg v "$3" \
        --arg e "$4" --arg d "$distro" '
        "pkg:rpm/\($ns)/\($n)"
        + (if $v == "" then "" else "@" + ($v | @uri) end)
        + "?arch=\($a)"
        + (if $e == "" then "" else "&epoch=\($e)" end)
        + "&distro=\($d)"'
}

# ---------------------------------------------------------------------
# Binding external components to packages
# ---------------------------------------------------------------------

# Print "NAME<tab>EPOCH<tab>VERSION-RELEASE<tab>ARCH<tab>SOURCERPM" (EPOCH
# is "-" when unset, as read merges consecutive tabs) of the
# package owning file $1, or nothing.
owner() {
    rpm -qf --qf '%{NAME}\t%{EPOCH}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n' \
        "$1" 2>/dev/null | sed -e 's/\t(none)\t/\t-\t/' -e q || true
}

# One line per external component: its bound form, as JSON.
bind_externals() {
    $JQ -c '.components[] | select(.isExternal == true)' "$build_sbom" \
    | while read -r comp; do
        ref=`printf '%s' "$comp" | $JQ -r '."bom-ref"'`
        owners=
        for path in `printf '%s' "$comp" | $JQ -r '.evidence.occurrences[]?.location'`; do
            o=`owner "$path"`
            if test -z "$o"; then
                warn "$ref: no package owns $path"
                continue
            fi
            case "
$owners" in
              *"
$o"*) ;;
              *) owners="$owners
$o" ;;
            esac
        done
        if test -z "$owners"; then
            warn "$ref: not bound to a package"
            printf '%s\n' "$comp"
            continue
        fi
        multi=false
        test `printf '%s\n' "$owners" | sed '/^$/d' | wc -l` -le 1 || multi=true
        printf '%s\n' "$owners" | sed '/^$/d' \
        | while IFS='	' read -r name pepoch pvr parch srpm; do
            test "$pepoch" != - || pepoch=
            printf '%s' "$comp" | $JQ -c \
                --arg name "$name" --arg evr "${pepoch:+$pepoch:}$pvr" \
                --arg purl "`purl "$name" "$parch" "$pvr" "$pepoch"`" \
                --arg srpm "$srpm" --arg vendor "$vendor" \
                --argjson multi "$multi" '
                { type: "library",
                  "bom-ref": (if $multi then ."bom-ref" + ":" + $name else ."bom-ref" end),
                  supplier: { name: $vendor },
                  name: $name,
                  version: $evr,
                  isExternal: true,
                  description: .description,
                  scope: "required",
                  purl: $purl,
                  properties: ((.properties // [])
                    + [ { name: "rpm:source-rpm", value: $srpm },
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

# One JSON patch object per line, for the patch files given as arguments.
patches_json() {
    for p in "$@"; do
        test -f "$p" || die "$p not found"
        $JQ -c -R -s --arg name "`basename "$p"`" '
            { type: "unofficial",
              diff: { text: { contentType: "text/x-diff", content: . },
                      url: $name } }' < "$p"
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
test $want_externals = no || externals=`bind_externals`

# Components of the upstream source SBOM to add.
extra=
for ref in $add_components; do
    c=`$JQ -c --arg ref "$ref" '.components[] | select(."bom-ref" == $ref)' "$source_sbom"`
    test -n "$c" || die "$ref: not in $source_sbom"
    extra="$extra
$c"
done

# The patches embed their full text, which can exceed the size limit of
# a command line argument, so they are passed to jq in a file.
patches_file=`mktemp`
trap 'rm -f "$patches_file"' EXIT
patches_json "$@" > "$patches_file"
pkg_purl=`purl "$package" "$arch" "$vr" "$epoch"`

# Assemble the package SBOM from the bound externals and extra
# components on stdin.
assemble() {
    $JQ -s \
    --slurpfile build "$build_sbom" \
    --arg package "$package" --arg version "$version" --arg purl "$pkg_purl" \
    --arg vendor "$vendor" --arg installed "$installed_as" \
    --arg epoch "${SOURCE_DATE_EPOCH:-}" \
    --slurpfile patches "$patches_file" '
    . as $added
    | $build[0] as $b
    | ($installed | split(",")) as $want
    | [ $b.components[]
        | select(.isExternal != true)
        | select(any(.properties[]?; .name == "apr:installed-as"
                                     and (.value as $v | any($want[]; . == $v)))) ]
      as $bundled
    | ($bundled + $added) as $components
    | { "$schema": $b."$schema",
        bomFormat: "CycloneDX",
        specVersion: $b.specVersion,
        version: 1,
        metadata: (
          (if $epoch == "" then {}
           else { timestamp: ($epoch | tonumber | floor | todate) } end)
          + {
            # "build": the SBOM is made during the package build, from
            # the dependencies resolved in the build environment.
            lifecycles: [ { phase: "build" } ],
            tools: {
              components: ($b.metadata.tools.components
                + [ { type: "application", name: "apr-sbom-bind.sh",
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
        components: $components,
        dependencies: [
          { ref: $package,
            dependsOn: [ $components[]
                         | select(.scope != "excluded") | ."bom-ref" ] } ] }'
}

bom=`printf '%s\n%s\n' "$externals" "$extra" | sed '/^$/d' | assemble`

# serialNumber: version 5 UUID (URL namespace) of
# PURL#sbom=build[&source_date_epoch=EPOCH][&sha256=DIGEST], the digest
# being added only when SOURCE_DATE_EPOCH is unset.

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

name="$pkg_purl#sbom=build"
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
