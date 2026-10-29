#!/bin/sh

# Compare the candidate tarball built by r1-release.sh with the latest
# released tarball of the same project in https://dist.apache.org/repos/dist/release/apr/
#
# USAGE: r1b-compare-release.sh [options] [version]
# EXAMPLE: r1b-compare-release.sh
#          r1b-compare-release.sh -q
#          r1b-compare-release.sh -r 1.7.5 -g
#
# This script is called in the same svn checkout r0/r1 were run in. It
# downloads the latest release of PROJECT (apr or apr-util, from the
# checkout) for the same major.minor stream, verifies its sha256, unpacks
# both tarballs under dist/compare/ and runs a recursive diff. Nothing is
# committed or uploaded.

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  compare the candidate tarball in the local 'dist' directory (created by
  r1-release.sh) with the latest release in ${SVN_DIST_URL:-https://dist.apache.org/repos/dist/}release/apr/.
  If no version is given, the version recorded in dist/VERSION is used.
  Arguments:
    version        as 'm.n.p(-suffix)?' the candidate version to compare.
  Options:
    -h             print usage information
    -r REL         compare against release REL (e.g. 1.7.5) instead of the
                   latest release in the same major.minor stream
    -q             brief: only list files that differ, were added or removed
    -g             include generated autotools files (configure, build/*.m4,
                   ltmain.sh, ...), which are excluded by default
    -x PATTERN     additionally exclude files matching PATTERN (repeatable)
    -k             keep an already downloaded release tarball, do not re-fetch
EOF
  exit 1
}

DIFF_OPTS="-u"
INCLUDE_GENERATED=0
KEEP_DOWNLOAD=0
EXTRA_EXCLUDES=""
RELEASE_VERSION=""

while getopts "hr:qgx:k" opt; do
    case $opt in
        h)  usage
            ;;
        r)  RELEASE_VERSION="$OPTARG"
            ;;
        q)  DIFF_OPTS="-q"
            ;;
        g)  INCLUDE_GENERATED=1
            ;;
        x)  EXTRA_EXCLUDES="$EXTRA_EXCLUDES $OPTARG"
            ;;
        k)  KEEP_DOWNLOAD=1
            ;;
        *)  usage
            ;;
    esac
done
shift $((OPTIND-1))

source `dirname $0`/common-lib.sh
source `dirname $0`/env.sh

detect_checkout
detect_version $1

case "$PROJECT" in
  apr|apr-util|apr-iconv) ;;
  *) fail "unknown project '$PROJECT', expected apr, apr-util or apr-iconv" ;;
esac

TAR_BASENAME="${PROJECT}-${FULL_VERSION}-candidate"
CAND_TGZ="${DIST_DIR}/${TAR_BASENAME}.tar.gz"
# release.sh strips -rcX-candidate from the directory inside the tarball
CAND_DIRNAME="${PROJECT}-${VERSION}"

test -f "${CAND_TGZ}" ||
  fail "candidate tarball ${CAND_TGZ} does not exist. Did you run 'r1-release.sh'?"

# the dist area is always apr/, for all three projects
RELEASE_URL="${SVN_DIST_URL}release/apr"

# ---------------------------------------------------------------------
# determine the release to compare against
if test -z "${RELEASE_VERSION}"; then
  echo "listing releases in ${RELEASE_URL} ..."
  released=`svn ls "${RELEASE_URL}/" |
    grep -E "^${PROJECT}-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz\$" |
    sed -e "s/^${PROJECT}-//" -e 's/\.tar\.gz$//' |
    sort -t. -k1,1n -k2,2n -k3,3n` || true
  test -n "${released}" || fail "no ${PROJECT}-*.tar.gz found in ${RELEASE_URL}"

  # prefer the latest release in our own major.minor stream
  RELEASE_VERSION=`echo "${released}" | grep "^${v_major}\.${v_minor}\." | tail -1` || true
  if test -z "${RELEASE_VERSION}"; then
    RELEASE_VERSION=`echo "${released}" | tail -1`
    warn "no ${PROJECT} ${v_major}.${v_minor}.x release found, comparing against latest overall: ${RELEASE_VERSION}"
  fi
fi

if test "${RELEASE_VERSION}" = "${VERSION}"; then
  warn "release ${RELEASE_VERSION} has the same version as the candidate; is this a re-roll of a published release?"
fi

REL_BASENAME="${PROJECT}-${RELEASE_VERSION}"
REL_DIRNAME="${REL_BASENAME}"

# ---------------------------------------------------------------------
# fetch and verify the released tarball
COMPARE_DIR="${DIST_DIR}/compare"
mkdir -p "${COMPARE_DIR}"
REL_TGZ="${COMPARE_DIR}/${REL_BASENAME}.tar.gz"

if test "${KEEP_DOWNLOAD}" = 1 -a -f "${REL_TGZ}"; then
  echo "using already downloaded ${REL_TGZ}"
else
  echo "downloading ${RELEASE_URL}/${REL_BASENAME}.tar.gz ..."
  curl -sSfL -o "${REL_TGZ}" "${RELEASE_URL}/${REL_BASENAME}.tar.gz" ||
    fail "download of ${REL_BASENAME}.tar.gz failed"
  curl -sSfL -o "${REL_TGZ}.sha256" "${RELEASE_URL}/${REL_BASENAME}.tar.gz.sha256" ||
    fail "download of ${REL_BASENAME}.tar.gz.sha256 failed"
fi

if test -f "${REL_TGZ}.sha256"; then
  openssl version >/dev/null 2>&1 || fail "unable to find 'openssl' in path"
  expected=`awk '{print tolower($1)}' "${REL_TGZ}.sha256" | tr -d ' \r'`
  actual=`openssl sha256 -r "${REL_TGZ}" | awk '{print tolower($1)}'`
  if test -z "${expected}" -o "${expected}" != "${actual}"; then
    fail "sha256 mismatch for ${REL_TGZ}: expected '${expected}', got '${actual}'"
  fi
  echo "sha256 of ${REL_BASENAME}.tar.gz verified"
fi

# ---------------------------------------------------------------------
# unpack both into fresh directories
CAND_X="${COMPARE_DIR}/candidate"
REL_X="${COMPARE_DIR}/release"
rm -rf "${CAND_X}" "${REL_X}"
mkdir -p "${CAND_X}" "${REL_X}"

echo "unpacking ${CAND_TGZ} ..."
tar xzf "${CAND_TGZ}" -C "${CAND_X}"
echo "unpacking ${REL_TGZ} ..."
tar xzf "${REL_TGZ}" -C "${REL_X}"

test -d "${CAND_X}/${CAND_DIRNAME}" ||
  fail "candidate tarball did not unpack to ${CAND_DIRNAME}/, found: `ls ${CAND_X}`"
test -d "${REL_X}/${REL_DIRNAME}" ||
  fail "release tarball did not unpack to ${REL_DIRNAME}/, found: `ls ${REL_X}`"

# ---------------------------------------------------------------------
# compare the set of published artifacts, so a missing .bz2/.zip/.asc
# in the candidate stands out
echo ""
echo "artifact types published for ${REL_BASENAME} vs. present for ${TAR_BASENAME}:"
rel_artifacts=`svn ls "${RELEASE_URL}/" | grep "^${REL_BASENAME}[.-]" | sed -e "s/^${REL_BASENAME}//"` || true
missing=0
for suffix in ${rel_artifacts}; do
  if test -f "${DIST_DIR}/${TAR_BASENAME}${suffix}"; then
    echo "  ok       ${TAR_BASENAME}${suffix}"
  else
    echo "  MISSING  ${TAR_BASENAME}${suffix}"
    missing=1
  fi
done
if test "${missing}" = 1; then
  warn "the candidate is missing artifacts that ${REL_BASENAME} published"
fi

# ---------------------------------------------------------------------
# diff the trees
EXCLUDES=""
if test "${INCLUDE_GENERATED}" != 1; then
  # files (re)generated by buildconf which differ with every autotools
  # version and drown out the real changes
  for pat in configure aclocal.m4 libtool.m4 ltoptions.m4 ltsugar.m4 \
             ltversion.m4 lt~obsolete.m4 ltmain.sh config.guess config.sub \
             apr_common.m4 'autom4te*.cache' '*.orig' '*.rej'; do
    EXCLUDES="${EXCLUDES} -x ${pat}"
  done
fi
for pat in ${EXTRA_EXCLUDES}; do
  EXCLUDES="${EXCLUDES} -x ${pat}"
done

echo ""
echo "diff ${DIFF_OPTS} -r -N${EXCLUDES} ${REL_X}/${REL_DIRNAME} ${CAND_X}/${CAND_DIRNAME}"
echo "---------------------------------------------------------------------"
rc=0
diff ${DIFF_OPTS} -r -N ${EXCLUDES} "${REL_X}/${REL_DIRNAME}" "${CAND_X}/${CAND_DIRNAME}" || rc=$?
echo "---------------------------------------------------------------------"
case "${rc}" in
  0) echo "no differences between ${REL_BASENAME} and ${TAR_BASENAME} (excluded generated files aside)" ;;
  1) echo "differences found between ${REL_BASENAME} and ${TAR_BASENAME}" ;;
  *) fail "diff failed with exit code ${rc}" ;;
esac

echo ""
echo "unpacked trees remain in ${REL_X}/${REL_DIRNAME} and ${CAND_X}/${CAND_DIRNAME} for further inspection."
hints=""
test "${INCLUDE_GENERATED}" != 1 && hints="-g to include generated autotools files"
test "${DIFF_OPTS}" != "-q" && hints="${hints}${hints:+, }-q for a file-level summary"
test -n "${hints}" && echo "rerun with ${hints}."
echo "If the candidate looks reasonable, run `dirname $0`/r2-prep-vote.sh to publish it for a vote."
