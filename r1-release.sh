#!/bin/sh

# Build the release candidate tarballs by calling release.sh with the
# parameters r0-make-candidate.sh determined and stashed in dist/VERSION.
#
# USAGE: r1-release.sh [options] [version]
# EXAMPLE: r1-release.sh -u covener@apache.org
#
# This script is called in the same svn checkout r0-make-candidate.sh was
# run in. It reconstructs PROJECT and TAG for release.sh from the checkout
# and dist/VERSION, so they do not have to be copied from r0's output.

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  build the candidate tarballs, checksums and signatures into the local
  'dist' directory by calling release.sh with the PROJECT and TAG that
  r0-make-candidate.sh determined. If no version is given, the version
  recorded by r0-make-candidate.sh in dist/VERSION is used.
  Arguments:
    version        as 'm.n.p(-suffix)?' the version to use.
  Options:
    -h             print usage information
    -y             never ask, always assume yes
    -u USER        key to sign with (default: \$SIGNING_USER, else gpg default key)
    -a DIR         local APR source directory, needed for apr-util's buildconf
                   (default: \$APR_SOURCE)
EOF
  exit 1
}

while getopts "hyu:a:" opt; do
    case $opt in
        h)  usage
            ;;
        y)  ALWAYS_YES=1
            ;;
        u)  SIGNING_USER="$OPTARG"
            ;;
        a)  APR_SOURCE="$OPTARG"
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

TAG="${FULL_VERSION}-candidate"
SVN_DEST="tags/${TAG}"

svn ls "$SVN_BASE/$SVN_DEST" >/dev/null 2>&1 ||
  fail "release candidate tag does not exist in SVN: $SVN_DEST. Did you run r0-make-candidate.sh?"

if test "$PROJECT" = "apr-util"; then
  if test -z "$APR_SOURCE"; then
    warn "no APR source directory given (-a DIR or \$APR_SOURCE); apr-util's buildconf may fail to find APR"
    if ! ask_yes_no "Do you want to continue anyway?"; then
      exit 1
    fi
  elif test ! -d "$APR_SOURCE"; then
    fail "APR source directory does not exist: $APR_SOURCE"
  fi
fi

# release.sh moves its output into ./dist relative to the current directory
mkdir -p "${DIST_DIR}"

cat <<EOF
building release candidate tarballs:
  PROJECT: $PROJECT
  TAG: $TAG
  VERSION: $FULL_VERSION
  SIGNING_USER: ${SIGNING_USER:-<gpg default key>}
  APR_SOURCE: ${APR_SOURCE:-<none>}
  OUTPUT: ${DIST_DIR}/${PROJECT}-${TAG}.*

EOF
if ! ask_yes_no "Is this as expected?"; then
  exit 1
fi

# record the version in dist/VERSION so later stages pick it up, in case
# it was given explicitly here rather than taken from r0's stash.
save_version

# release.sh accepts empty optional args and treats them as unset.
"`dirname $0`"/release.sh "$PROJECT" "$TAG" "$SIGNING_USER" "$APR_SOURCE" ||
  fail "release.sh failed, see above. No release candidate tarballs were produced."

echo ""
echo "verifying checksums and signatures in ${DIST_DIR}:"
verify_dist_files "${DIST_DIR}/${PROJECT}-${TAG}.tar.gz" \
                  "${DIST_DIR}/${PROJECT}-${TAG}.tar.bz2" \
                  "${DIST_DIR}/${PROJECT}-${TAG}-win32-src.zip"

echo ""
echo "release candidate tarballs created in ${DIST_DIR}:"
ls -1 "${DIST_DIR}"/"${PROJECT}-${TAG}"*
echo ""
echo "Review them, then run `dirname $0`/r2-prep-vote.sh to publish them for a vote."
