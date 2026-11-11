#!/bin/sh
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# sbom.sh -- generate CycloneDX 1.7 SBOMs for APR
#
# Usage:
#   build/sbom.sh source [SRCDIR]
#       Write the source SBOM to stdout.  It lists the parts of the APR
#       source tree that are not copyright The Apache Software Foundation,
#       and every external library the UNIX build may link against, with
#       the range of versions APR accepts.  Needs only the source tree.
#
#   build/sbom.sh build --srcdir DIR [--host TRIPLET] [--cross yes|no|maybe]
#                       [--libs "LIBS"] [--objects "OBJECTS"]
#                       [--library LIBAPR.la] [--cc "CC"]
#       Write the build SBOM to stdout.  Run from a configured build
#       directory (the Makefile's "sbom" target does this).  It lists the
#       third-party code from maintained upstreams compiled into this
#       build of libapr (code forked long ago, marked "historical" in
#       components.json, is only in the source SBOM) and the
#       concrete libraries it needs at run time, with the versions found
#       on the build system where they can be determined.  These are read
#       from the shared library built from LIBAPR.la (falling back to the
#       -l flags in LIBS), and CC is asked for the file each of them
#       resolved to, which packaging tools can map to their packages.
#
# The components come from build/sbom/components.json.  Licenses and
# copyrights of bundled code are read from the SPDX tags in the source
# files; the script fails if a file carries a license tag other than
# Apache-2.0 that no entry in components.json accounts for.
#
# Environment:
#   SOURCE_DATE_EPOCH  If set, used as the SBOM timestamp.
#   JQ                 jq program (default: jq); jq 1.5 or later is required.
#   PKG_CONFIG         pkg-config program (default: pkg-config).
#
# Only the UNIX build is supported for now.

set -e

# Glob order, sorting and pattern matching must not depend on the
# locale, or the output would not be reproducible.
LC_ALL=C
export LC_ALL

# bash applies set -e to command substitutions only in POSIX mode (as
# sh) or with inherit_errexit; configure may have chosen bash as SHELL.
if (shopt -s inherit_errexit) >/dev/null 2>&1; then
    shopt -s inherit_errexit
fi

# Field separator of the records about files: file names may contain
# blanks or tabs, but not this control character.
SEP=`printf '\034'`

usage() {
    sed -n '/^# Usage:/,/^# The components/p' "$0" | sed '$d' \
        | sed 's/^# \{0,1\}//' >&2
    exit 1
}

die() {
    echo "$0: $*" >&2
    exit 1
}

mode=$1
test -n "$mode" || usage
shift

srcdir=
host=
cross=no
libs=
objects=
library=
cc=

case $mode in
  source)
    srcdir=${1:-.}
    ;;
  build)
    while test $# -gt 0; do
        test $# -ge 2 || usage
        case $1 in
          --srcdir)  srcdir=$2 ;;
          --host)    host=$2 ;;
          --cross)   cross=$2 ;;
          --libs)    libs=$2 ;;
          --objects) objects=$2 ;;
          --library) library=$2 ;;
          --cc)      cc=$2 ;;
          *)         usage ;;
        esac
        shift 2
    done
    test -n "$srcdir" || usage
    ;;
  *)
    usage
    ;;
esac

test -f "$srcdir/include/apr_version.h" \
    || die "$srcdir is not an APR source tree"

DATA=$srcdir/build/sbom/components.json
test -f "$DATA" || die "$DATA not found"

JQ=${JQ:-jq}
PKG_CONFIG=${PKG_CONFIG:-pkg-config}

$JQ -n 'empty' >/dev/null 2>&1 \
    || die "jq is required to generate SBOMs (set JQ to its path)"

# jq definitions shared by the programs below.
#   opt(k; v): {k: v}, or {} when v is the empty string or null
#   uniq:      the array without duplicates, keeping the first of each
JQ_LIB='
def opt(k; v): if v == "" or v == null then {} else {(k): v} end;
def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
'

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

# Is object file $1 (e.g. misc/unix/getopt.lo) part of this build?
in_build() {
    case " $objects " in
      *" $1 "*) return 0 ;;
    esac
    return 1
}

# Look up a version through pkg-config; prints nothing on failure.
pc_version() {
    $PKG_CONFIG --modversion "$1" 2>/dev/null || true
}

# Print the existing files matching the shell patterns $@, relative to
# the source directory, one per line.  IFS is emptied so that a pattern
# is expanded as a whole, not split on blanks first.
expand_files() {
    (
        cd "$srcdir" || exit 1
        IFS=
        for _p in "$@"; do
            for _f in $_p; do
                test ! -f "$_f" || printf '%s\n' "$_f"
            done
        done
    )
}

# ---------------------------------------------------------------------
# SPDX tags
#
# Every file in the source tree containing "SPDX-" is read for these
# tags, each on a comment line of its own:
#
#   SPDX-License-Identifier, SPDX-FileCopyrightText, SPDX-FileContributor
#   SPDX-SnippetBegin, SPDX-SnippetCopyrightText, SPDX-SnippetEnd
#
# A license or copyright tag between SnippetBegin and SnippetEnd applies
# to the snippet, otherwise to the whole file.  The result is a JSON
# object keyed by file name:
#
#   { "FILE": { "license": "...", "copyright": [...], "contributor": [...],
#               "snippets": [ { "line": N, "end": N, "license": "...",
#                               "copyright": [...] } ] } }
#
# File names are passed as data, never as command arguments, so they
# may contain blanks, quotes or tabs; only newlines are not supported.
# ---------------------------------------------------------------------

# Print the files of the source tree, relative to it, one per line,
# except those matching a scan-exclude pattern.
source_files() {
    _excl=`$JQ -r '."scan-exclude"[]' "$DATA"` || exit 1
    _all=`cd "$srcdir" && find . \( -name .git -o -name .svn \
              -o -name autom4te.cache -o -name .libs -o -name .deps \
              -o -name 'cmake-build-*' \) -prune -o -type f -print` \
        || die "cannot list the files of $srcdir"
    # Split on newlines only, and do not expand the patterns as globs.
    _ifs=$IFS
    IFS='
'
    set -f
    for _f in $_all; do
        _f=${_f#./}
        for _x in $_excl; do
            case $_f in
              $_x) continue 2 ;;
            esac
        done
        printf '%s\n' "$_f"
    done
    set +f
    IFS=$_ifs
}

# Reads file names on stdin and prints one record per tag, its fields
# separated by \034 (FILE, F or S, snippet start line, key, value).
# Exits with status 2 if a file cannot be read.
AWK_TAGS='
BEGIN { SEP = "\034"; status = 0 }
$0 != "" {
    file = $0
    path = "./" file
    snip = 0
    n = 0
    while ((r = (getline line < path)) > 0) {
        n++
        if (index(line, "SPDX-"))
            tag_line(line)
    }
    if (r < 0) {
        print "cannot read " file | "cat 1>&2"
        status = 2
    }
    close(path)
}
END { exit status }

function emit(kind, start, key, val) {
    print file SEP kind SEP start SEP key SEP val
}

function tag_line(line,    tag, val, key) {
    if (line !~ /^[ \t]*(\/\*+|\*|#+|\/\/|dnl)?[ \t]*SPDX-[A-Za-z]/)
        return
    sub(/^[ \t]*(\/\*+|\*|#+|\/\/|dnl)?[ \t]*/, "", line)
    tag = line
    sub(/[: \t].*$/, "", tag)
    val = ""
    if (index(line, ":")) {
        val = line
        sub(/^[^:]*:[ \t]*/, "", val)
        sub(/[ \t]*\*\/[ \t]*$/, "", val)
        sub(/[ \t]+$/, "", val)
    }
    if (tag == "SPDX-SnippetBegin") {
        snip = n
        emit("S", snip, "begin", "")
        return
    }
    if (tag == "SPDX-SnippetEnd") {
        emit("S", snip, "end", n)
        snip = 0
        return
    }
    if (tag == "SPDX-License-Identifier")
        key = "license"
    else if (tag == "SPDX-FileCopyrightText" || tag == "SPDX-SnippetCopyrightText")
        key = "copyright"
    else if (tag == "SPDX-FileContributor")
        key = "contributor"
    else
        return
    if (snip)
        emit("S", snip, key, val)
    else
        emit("F", 0, key, val)
}
'

# The list of files and the output of awk are kept in variables, not
# piped, so that set -e (or the explicit checks) sees their failures.
scan_tags() {
    _files=`source_files` || exit 1
    _records=`printf '%s\n' "$_files" | (cd "$srcdir" && awk "$AWK_TAGS")` \
        || die "cannot read the SPDX tags of $srcdir"
    printf '%s\n' "$_records" | $JQ -R -s '
        [ split("\n")[] | select(. != "") | split("\u001c")
          | { file: .[0], kind: .[1], snip: (.[2] | tonumber),
              key: .[3], val: .[4] } ]
        | group_by(.file)
        | map(. as $r
              | { key: $r[0].file,
                  value: {
                    license: ([ $r[] | select(.kind == "F" and .key == "license")
                                | .val ][0] // ""),
                    copyright: [ $r[] | select(.kind == "F" and .key == "copyright")
                                 | .val ],
                    contributor: [ $r[] | select(.kind == "F" and .key == "contributor")
                                   | .val ],
                    snippets: ([ $r[] | select(.kind == "S") ]
                               | group_by(.snip)
                               | map(. as $s
                                     | { line: $s[0].snip,
                                         end: ([ $s[] | select(.key == "end")
                                                 | .val | tonumber ][0]),
                                         license: ([ $s[] | select(.key == "license")
                                                     | .val ][0] // ""),
                                         copyright: [ $s[] | select(.key == "copyright")
                                                      | .val ] })) } })
        | from_entries'
}

# Texts of the LicenseRef-* licenses, from LICENSES/, keyed by identifier.
license_refs() {
    _refs='{}'
    for _f in "$srcdir"/LICENSES/LicenseRef-*.txt; do
        test -f "$_f" || continue
        _id=`basename "$_f" .txt`
        _refs=`$JQ -c -R -s --argjson refs "$_refs" --arg id "$_id" \
                   '$refs + { ($id): . }' < "$_f"`
    done
    printf '%s\n' "$_refs"
}

# ---------------------------------------------------------------------
# Bundled third-party code
#
# Prints one JSON component per line and appends to $claims the files
# each entry accounts for ("FILE<SEP>LICENSE", or "FILE<SEP>*" for
# untagged entries).
# ---------------------------------------------------------------------

claims=

bundled_components() {
    _n=`$JQ '.bundled | length' "$DATA"`
    _i=0
    while test $_i -lt $_n; do
        _entry=`$JQ -c ".bundled[$_i]" "$DATA"`
        _i=`expr $_i + 1`

        _ref=`printf '%s' "$_entry" | $JQ -r '.component."bom-ref"'`
        _lic=`printf '%s' "$_entry" | $JQ -r '.license'`
        _tagged=`printf '%s' "$_entry" | $JQ -r '.tagged != false'`
        _ifpresent=`printf '%s' "$_entry" | $JQ -r '."if-present" == true'`
        _scope=`printf '%s' "$_entry" | $JQ -r '.scope // "required"'`
        _upstream=`printf '%s' "$_entry" | $JQ -r '.upstream // ""'`

        # The patterns and the files they match are split on newlines
        # only, as file names may contain blanks.
        _ifs=$IFS
        IFS='
'
        set -f
        set -- `printf '%s' "$_entry" | $JQ -r '.files[]'`
        set +f
        IFS=$_ifs
        _files=`expand_files "$@"` || exit 1
        if test -z "$_files"; then
            test "$_ifpresent" = true && continue
            die "$_ref: none of its files exist: $*"
        fi
        if test "$_ifpresent" != true; then
            for _p in "$@"; do
                test -f "$srcdir/$_p" || die "$_ref: $_p does not exist"
            done
        fi

        IFS='
'
        set -f
        for _f in $_files; do
            if test "$_tagged" = true; then
                claims="$claims$_f$SEP$_lic
"
            else
                claims="$claims$_f$SEP*
"
            fi
        done
        set +f
        IFS=$_ifs

        # The build SBOM lists only code from a maintained upstream, whose
        # advisories could apply to this build; code forked long ago is
        # only of interest for license compliance, in the source SBOM.
        # There, apr:installed-as tells packagers where the code ends up:
        # "library" (compiled into libapr) or "header" (only in installed
        # headers).  The files of skipped entries stay claimed above.
        _installed=
        if test "$mode" = build; then
            test "$_scope" != excluded || continue
            test "$_upstream" != historical || continue
            for _o in `printf '%s' "$_entry" | $JQ -r '(.objects // [])[]'`; do
                if test "$_o" = -; then
                    test -n "$_installed" || _installed=header
                elif in_build "$_o"; then
                    _installed=library
                fi
            done
            test -n "$_installed" || continue
            _scope=required
        fi

        _extracted='{}'
        for _k in `printf '%s' "$_entry" | $JQ -r '(.extract // {}) | keys[]'`; do
            _file=`printf '%s' "$_entry" | $JQ -r --arg k "$_k" '.extract[$k].file'`
            _sed=`printf '%s' "$_entry" | $JQ -r --arg k "$_k" '.extract[$k].sed'`
            # The file may be missing from an entry with if-present.
            test -f "$srcdir/$_file" || continue
            _v=`sed -n "$_sed" "$srcdir/$_file"` \
                || die "$_ref: cannot read $_file"
            _v=`printf '%s\n' "$_v" | sed q`
            _extracted=`$JQ -nc --argjson o "$_extracted" --arg k "$_k" --arg v "$_v" \
                            '$o + { ($k): $v }'`
        done

        $JQ -nc \
            --argjson entry "$_entry" --argjson tags "$tags" \
            --argjson extracted "$_extracted" --argjson refs "$refs" \
            --arg files "$_files" --arg scope "$_scope" --arg tagged "$_tagged" \
            --arg installed "$_installed" --arg upstream "$_upstream" \
            "$JQ_LIB"'
            $entry.license as $lic
            | $entry.component."bom-ref" as $ref
            | [ $files | split("\n")[] | select(. != "") ] as $fl
            | (if $tagged == "true" then
                 [ $fl[] as $f
                   | ($tags[$f] // error("\($f): no SPDX tags, needed by \($ref)"))
                   | [ .snippets[] | select(.license == $lic) ] as $sn
                   | if ($sn | length) > 0 then
                       $sn[] | { location: $f, line: .line,
                                 copyright: .copyright, contributor: [] }
                     elif .license == $lic then
                       { location: $f, copyright: .copyright,
                         contributor: .contributor }
                     else
                       error("\($f): no SPDX-License-Identifier \"\($lic)\", needed by \($ref)")
                     end ]
               else
                 [ $fl[] | { location: ., copyright: [], contributor: [] } ]
               end) as $occ
            | ([ $occ[].copyright[] ]
               + [ $entry.copyright // empty ]
               + [ $extracted.copyright // empty | select(. != "") ]
               | uniq) as $copyright
            | ([ $occ[].contributor[] ] | uniq) as $contributors
            | ([ $extracted | to_entries[]
                 | select(.key != "version" and .key != "copyright"
                          and .value != "")
                 | { name: .key, value: .value } ]
               + (if $upstream == "" then []
                  else [ { name: "apr:upstream", value: $upstream } ] end)
               + (if $installed == "" then []
                  else [ { name: "apr:installed-as", value: $installed } ] end))
              as $props
            | (if ($lic | contains(" ") | not)
                  and ($lic | startswith("LicenseRef-") | not)
               then { license: { id: $lic } }
               else { expression: $lic }
                    + ([ $lic | split(" ")[] | ltrimstr("(") | rtrimstr(")")
                         | select(startswith("LicenseRef-"))
                         | select($refs[.] != null)
                         | { licenseIdentifier: ., text: { content: $refs[.] } } ]
                       | if length > 0 then { expressionDetails: . } else {} end)
               end) as $license
            | $entry.component
              + opt("version"; $extracted.version)
              + (if ($contributors | length) > 0 then
                   { authors: [ $contributors[] | split(" <") as $p
                                | { name: $p[0] }
                                  + opt("email"; ($p[1] // "") | rtrimstr(">")) ] }
                 else {} end)
              + { isExternal: false,
                  scope: $scope,
                  licenses: [ $license ] }
              + opt("copyright"; $copyright | join("\n"))
              + (if ($props | length) > 0 then { properties: $props } else {} end)
              + { evidence: { occurrences: [ $occ[] | { location }
                                             + opt("line"; .line) ] } }'
    done
}

# Fail if a file carries a license tag (other than Apache-2.0) that no
# bundled entry accounts for, or a snippet is malformed.
check_claims() {
    _errors=`printf '%s' "$claims" | $JQ -r -R -s --argjson tags "$tags" '
        [ split("\n")[] | select(. != "") | split("\u001c")
          | { file: .[0], license: .[1] } ] as $claims
        | def claimed($f; $l):
            any($claims[]; .file == $f and (.license == $l or .license == "*"));
          $tags | to_entries[] | .key as $f | .value
          | (if .license != "" and .license != "Apache-2.0"
                and (claimed($f; .license) | not)
             then "\($f): license \(.license) is not described in build/sbom/components.json"
             else empty end),
            (.snippets[]
             | if .end == null then "\($f):\(.line): SPDX-SnippetBegin without SPDX-SnippetEnd"
               elif .license == "" then "\($f):\(.line): snippet without SPDX-License-Identifier"
               elif claimed($f; .license) | not
               then "\($f):\(.line): snippet license \(.license) is not described in build/sbom/components.json"
               else empty end)'`
    if test -n "$_errors"; then
        printf '%s\n' "$_errors" | sed "s|^|$0: |" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------
# External libraries
# ---------------------------------------------------------------------

# Every library the UNIX configure script may add to LIBS, with the
# range of versions accepted.
source_externals() {
    $JQ -c '.external[]
            | { type: "library" } + .component
            + (if ."compile-only" then {} else { isExternal: true } end)' "$DATA"
}

# build_external ENTRY OVERRIDE VERSION LIB KIND LABELS PATHS
#
# Print a component of the build SBOM: ENTRY's component (or a generic
# one for library LIB when ENTRY is empty) with the OVERRIDE fields and
# the VERSION found.  KIND says what LABELS are: "soname" (the
# libraries libapr needs at run time, recorded one property each) or
# "link-flags" (the -l flags it was linked with).  PATHS are the files
# the libraries resolved to at build time, one per line.
build_external() {
    _e=${1:-null}
    _o=${2:-}
    test -n "$_o" || _o='{}'
    $JQ -nc --argjson e "$_e" --argjson o "$_o" \
        --arg ver "$3" --arg lib "$4" --arg kind "$5" --arg labels "$6" \
        --arg paths "$7" \
        "$JQ_LIB"'
        ({ type: "library" }
         + (if $e == null then
              { "bom-ref": ("lib" + $lib), name: ("lib" + $lib),
                description: "System library linked by configure." }
            else $e.component end)
         + $o
         | del(.versionRange)
         | del(.scope))
        + opt("version"; $ver)
        | (if .cpe == null then .
           elif $ver == "" then del(.cpe)
           else .cpe |= (split("@VERSION@") | join($ver)) end)
        | . + (if $e != null and $e."compile-only" then { scope: "excluded" }
               else { isExternal: true, scope: "required" } end)
            + ([ $labels | split(" ")[] | select(. != "") ] as $l
               | if ($l | length) == 0 then {}
                 elif $kind == "soname" then
                   { properties: [ $l[] | { name: "apr:soname", value: . } ] }
                 else
                   { properties: [ { name: "apr:link-flags", value: ($l | join(" ")) } ] }
                 end)
            + ([ $paths | split("\n")[] | select(. != "") ] as $p
               | if ($p | length) > 0 then
                   { evidence: { occurrences: [ $p[] | { location: . } ] } }
                 else {} end)'
}

# Print the version and override fields of the first pkg-config module
# of ENTRY that is installed, as "VERSION<tab>OVERRIDE-JSON".
pc_lookup() {
    for _m in `printf '%s' "$1" | $JQ -r '(."pkg-config" // [])[].module'`; do
        _v=`pc_version "$_m"`
        if test -n "$_v"; then
            printf '%s\t%s\n' "$_v" "`printf '%s' "$1" | $JQ -c --arg m "$_m" \
                '[ ."pkg-config"[] | select(.module == $m) ][0].component // {}'`"
            return 0
        fi
    done
}

# Print the shared libraries (DT_NEEDED) that the shared library built
# from the libtool archive $library needs at run time, one per line.
# Prints nothing if there is no shared library or no tool to read it.
needed_libs() {
    test -n "$library" && test -f "$library" || return 0
    _dl=`sed -n "s/^dlname='\(.*\)'$/\1/p" "$library"`
    test -n "$_dl" || return 0
    _so=`dirname "$library"`/.libs/$_dl
    test -f "$_so" || return 0
    if (${READELF:-readelf} --version) >/dev/null 2>&1; then
        ${READELF:-readelf} -d "$_so" 2>/dev/null \
            | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p'
    elif (${OBJDUMP:-objdump} --version) >/dev/null 2>&1; then
        ${OBJDUMP:-objdump} -p "$_so" 2>/dev/null \
            | sed -n 's/^ *NEEDED  *\([^ ]*\) *$/\1/p'
    fi
}

# Print the file the compiler resolves library file name $1 to, or
# nothing.  The path is made absolute but symbolic links are kept, as
# packaging tools know libraries by the paths they install.
resolve_lib() {
    test -n "$cc" || return 0
    _p=`$cc -print-file-name="$1" 2>/dev/null` || return 0
    case $_p in
      /*) ;;
      *)  return 0 ;;
    esac
    test -f "$_p" || return 0
    _d=`dirname "$_p"`
    printf '%s/%s\n' "`cd "$_d" && pwd`" "`basename "$_p"`"
}

# Is library name $1 (e.g. "pthread", "ld-linux-x86-64") provided by
# the GNU C library?  .glibc.libs holds shell patterns.
in_glibc() {
    for _g in `$JQ -r '.glibc.libs[]' "$DATA"`; do
        case $1 in
          $_g) return 0 ;;
        esac
    done
    return 1
}

# Map the run-time dependencies of libapr onto the components that
# provide them.  They are read from the built shared library; if that is
# not possible (static-only build, no readelf/objdump, non-ELF system),
# the -l flags it was linked with are used instead.
build_externals() {
    glibc=
    if test "$cross" = no; then
        glibc=`getconf GNU_LIBC_VERSION 2>/dev/null | sed -n 's/^glibc //p'`
    fi

    needed=`needed_libs`
    if test -n "$needed"; then
        kind=soname
        items=$needed
    else
        kind=link-flags
        items=
        for flag in $libs; do
            case $flag in
              -l*) items="$items $flag" ;;
            esac
        done
    fi

    libc_labels=
    libc_paths=
    seen=
    emitted=
    for item in $items; do
        case $kind in
          soname) lib=`echo "$item" | sed -e 's/\.so.*$//' -e 's/^lib//'` ;;
          *)      lib=${item#-l} ;;
        esac
        case " $seen " in
          *" $item "*) continue ;;
        esac
        seen="$seen $item"
        path=
        test $kind != soname || path=`resolve_lib "$item"`

        entry=`$JQ -c --arg lib "$lib" \
            '[ .external[] | select(any((.libs // [])[]; . == $lib)) ][0] // empty' \
            "$DATA"`
        ver=
        override='{}'
        if test -n "$entry"; then
            found=`pc_lookup "$entry"`
            if test -n "$found"; then
                ver=`printf '%s' "$found" | cut -f1`
                override=`printf '%s' "$found" | cut -f2-`
            fi
        fi

        if test -z "$ver" && test -n "$glibc" && in_glibc "$lib"; then
            libc_labels="$libc_labels $item"
            test -z "$path" || libc_paths="$libc_paths$path
"
            continue
        fi

        line=`build_external "$entry" "$override" "$ver" "$lib" "$kind" "$item" "$path"`
        ref=`printf '%s' "$line" | $JQ -r '."bom-ref"'`
        case " $emitted " in
          *" $ref "*) continue ;;
        esac
        emitted="$emitted $ref"
        printf '%s\n' "$line"
    done

    if test -n "$glibc"; then
        build_external "`$JQ -c '.glibc' "$DATA"`" '{}' "$glibc" c \
            "$kind" "$libc_labels" "$libc_paths"
    else
        case " $emitted " in
          *" libc "*) ;;
          *)
            build_external "`$JQ -c '[ .external[] | select(any((.libs // [])[]; . == "c")) ][0]' \
                                 "$DATA"`" '{}' "" c "$kind" "$libc_labels" "$libc_paths"
            ;;
        esac
    fi

    # Dependencies selected by a macro in apr_private.h.
    # (A loop over a variable, not a pipeline, so that set -e applies.)
    defined=`$JQ -c '.external[] | select(.define)' "$DATA"`
    _ifs=$IFS
    IFS='
'
    set -f
    for entry in $defined; do
        IFS=$_ifs
        define=`printf '%s' "$entry" | $JQ -r '.define'`
        if grep "^#define $define 1" include/arch/unix/apr_private.h \
           >/dev/null 2>&1; then
            found=`pc_lookup "$entry"`
            build_external "$entry" "`printf '%s' "$found" | cut -f2-`" \
                "`printf '%s' "$found" | cut -f1`" "" "" "" ""
        fi
    done
    set +f
    IFS=$_ifs

    # The libtool script is installed with APR's build files.  Its
    # version line may end with a distribution suffix, as in
    # "libtool (GNU libtool) 2.6.2 Debian-2.6.2-3".
    if test -x libtool; then
        _ltv=`./libtool --version 2>/dev/null | sed q`
        $JQ -nc \
            --arg version "`printf '%s\n' "$_ltv" | sed -n 's/^.*(GNU libtool) \([0-9][0-9.]*\).*$/\1/p'`" \
            --arg full "`printf '%s\n' "$_ltv" | sed -n 's/^.*(GNU libtool) //p'`" \
            "$JQ_LIB"'
            { type: "application",
              "bom-ref": "gnu-libtool",
              supplier: { name: "Free Software Foundation, Inc." },
              name: "GNU Libtool" }
            + opt("version"; $version)
            + { isExternal: false,
                description: "libtool script generated by configure and installed in APR'"'"'s build directory.",
                scope: "excluded",
                licenses: [ { expression: "GPL-2.0-or-later WITH Libtool-exception" } ],
                properties: ([ { name: "apr:installed-as", value: "build-file" } ]
                  + (if $full == "" then []
                     else [ { name: "apr:libtool:version-string", value: $full } ] end)),
                evidence: { occurrences: [ { location: "libtool" } ] } }'
    fi
}

# ---------------------------------------------------------------------
# Serial number
# ---------------------------------------------------------------------

# hexdigest BITS: print the SHA-1 (BITS=1) or SHA-256 (BITS=256) hex
# digest of stdin, or nothing if no tool for it is found.
hexdigest() {
    if (sha${1}sum </dev/null) >/dev/null 2>&1; then
        sha${1}sum | sed 's/ .*//'
    elif (shasum -a $1 </dev/null) >/dev/null 2>&1; then
        shasum -a $1 | sed 's/ .*//'
    elif (openssl dgst -sha$1 </dev/null) >/dev/null 2>&1; then
        openssl dgst -sha$1 | sed 's/^.* //'
    fi
}

# The RFC 9562 URL namespace, 6ba7b811-9dad-11d1-80b4-00c04fd430c8, as
# printf octal escapes.
NS_URL='\153\247\270\021\235\255\021\321\200\264\000\300\117\324\060\310'

# uuid5 NAME: print the RFC 9562 version 5 UUID of NAME in the URL
# namespace, or nothing if no SHA-1 tool is found.
uuid5() {
    _h=`{ printf "$NS_URL"; printf '%s' "$1"; } | hexdigest 1`
    test -n "$_h" || return 0
    # The variant bits of byte 8 become 10.
    case `echo "$_h" | cut -c17` in
      0|4|8|c) _v=8 ;;
      1|5|9|d) _v=9 ;;
      2|6|a|e) _v=a ;;
      *)       _v=b ;;
    esac
    echo "$_h" | sed "s/^\(........\)\(....\).\(...\).\(...\)\(............\).*/\1-\2-5\3-$_v\4-\5/"
}

# ---------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------

version=`sh "$srcdir/build/get-version.sh" all "$srcdir/include/apr_version.h" APR`
if grep '^#define APR_IS_DEV_VERSION' "$srcdir/include/apr_version.h" \
   >/dev/null 2>&1; then
    version="$version-dev"
fi
copyright=`sed -n 's/^#define APR_COPYRIGHT "\(.*\)"$/\1/p' "$srcdir/include/apr_version.h"`
purl="pkg:software-id/apache.org/apr-portable-runtime@$version"

configure_opts=
if test "$mode" = build && test -x ./config.status; then
    configure_opts=`./config.status --config 2>/dev/null || true`
fi

# The configure options and link flags may contain the absolute paths of
# the build and source directories (e.g. in -ffile-prefix-map=DIR=.);
# they are recorded as @abs_builddir@ and @abs_srcdir@ instead, so that
# the SBOM does not depend on where the build happened.
abs_builddir=`pwd`
abs_srcdir=`cd "$srcdir" && pwd`

tags=`scan_tags`
refs=`license_refs`

# One JSON object per line, one line per component.  The bundled
# components are generated in this shell (not a subshell) so that
# $claims is kept for check_claims.
bundled=`bundled_components; echo "CLAIMS"; printf '%s' "$claims"`
claims=`printf '%s\n' "$bundled" | sed -n '/^CLAIMS$/,$p' | sed 1d`
bundled=`printf '%s\n' "$bundled" | sed '/^CLAIMS$/,$d'`
check_claims

if test "$mode" = source; then
    externals=`source_externals`
else
    externals=`build_externals`
fi

# Assemble the document from the component lines on stdin.
#
# The output is reproducible: there is a timestamp only when
# SOURCE_DATE_EPOCH is set, and the serial number is added afterwards.
# libapr depends on every component except the build-only ones.
assemble() {
    $JQ -s \
        --arg mode "$mode" --arg version "$version" --arg purl "$purl" \
        --arg copyright "$copyright" --arg epoch "${SOURCE_DATE_EPOCH:-}" \
        --arg host "$host" --arg opts "$configure_opts" --arg libs "$libs_flat" \
        --arg builddir "$abs_builddir" --arg srcdir "$abs_srcdir" \
        "$JQ_LIB"'
    # Replace the build and source directories, the longer one first.
    def anonymize:
      reduce ([ { path: $builddir, name: "@abs_builddir@" },
                { path: $srcdir, name: "@abs_srcdir@" } ]
              | map(select(.path != "" and .path != "/"))
              | sort_by(-(.path | length)))[] as $d
        (.; split($d.path) | join($d.name));
    { "$schema": "http://cyclonedx.org/schema/bom-1.7.schema.json",
      bomFormat: "CycloneDX",
      specVersion: "1.7",
      version: 1,
      metadata: (
        (if $epoch == "" then {}
         else { timestamp: ($epoch | tonumber | floor | todate) } end)
        + {
          lifecycles: [ { phase: (if $mode == "source" then "pre-build"
                                  else "build" end) } ],
          tools: {
            components: [
              { type: "application",
                name: "APR build/sbom.sh",
                version: $version } ] },
          component: (
            { type: "library",
              "bom-ref": "apr",
              supplier: {
                name: "The Apache Software Foundation",
                url: [ "https://www.apache.org/" ] },
              name: "apr",
              version: $version,
              description: "Apache Portable Runtime",
              licenses: [ { license: { id: "Apache-2.0" } } ] }
            + opt("copyright"; $copyright)
            + { cpe: "cpe:2.3:a:apache:portable_runtime:\($version):*:*:*:*:*:*:*",
                purl: $purl,
                externalReferences: [
                  { type: "website", url: "https://apr.apache.org/" },
                  { type: "distribution",
                    url: "https://release-catalog.apache.org/apr-portable-runtime/" },
                  { type: "vcs", url: "https://svn.apache.org/repos/asf/apr/apr/" },
                  { type: "issue-tracker", url: "https://bz.apache.org/bugzilla/" } ] }
            + (if $mode == "build" then
                 { properties: [
                     { name: "apr:build:host", value: $host },
                     { name: "apr:build:configure-options", value: ($opts | anonymize) },
                     { name: "apr:build:libs", value: ($libs | anonymize) } ] }
               else {} end)) }),
      components: .,
      dependencies: [
        { ref: "apr",
          dependsOn: [ .[] | select(.scope != "excluded") | ."bom-ref" ] } ] }'
}

libs_flat=`echo $libs`
bom=`printf '%s\n%s\n' "$bundled" "$externals" | sed '/^$/d' | assemble`

# serialNumber: a version 5 UUID (RFC 9562, URL namespace) of
#
#   PURL?sbom=PHASE[&source_date_epoch=EPOCH][&sha256=DIGEST]
#
# PHASE keeps the source and build SBOMs of a release apart.  DIGEST is
# the SHA-256 of the SBOM without the serial number; it is added for
# build SBOMs, whose content depends on the build system, and whenever
# SOURCE_DATE_EPOCH is unset, so that e.g. two release candidates of the
# same version do not share a serial number.  The serial number is left
# out if no SHA-1 tool is available.
if test "$mode" = source; then
    name="$purl?sbom=pre-build"
else
    name="$purl?sbom=build"
fi
if test -n "$SOURCE_DATE_EPOCH"; then
    name="$name&source_date_epoch=$SOURCE_DATE_EPOCH"
fi
if test "$mode" = build || test -z "$SOURCE_DATE_EPOCH"; then
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
