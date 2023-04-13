#!/bin/sh

# Create a release candidate for voting in a svn checkout
#
# USAGE: r0-make-candidate.sh [version]
# EXAMPLE: r0-make-candidate.sh 1.7.4
#
# This script is called in a built svn checkout of the branch for which
# a release candidate shall be made:
# @version       the version identifier, major.minor.patch, to use. If not given
#                it will determine the version from the local sources
#

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  create a release candidate in local SVN checkout.
  If no version is given, the current version in the checkout is used.
  Arguments:
    version        as 'm.n.p(-suffix)?' the version to use.
  Options:
    -h             print usage information
    -y             never ask, always assume yes
EOF
  exit 1
}

while getopts "hy" opt; do
    case $opt in
        h)  usage
            ;;
        y)  ALWAYS_YES=1
            ;;
    esac
done
shift $((OPTIND-1))

source `dirname $0`/common-lib.sh
source `dirname $0`/env.sh

detect_checkout
assure_clean_checkout
detect_version $1

SVN_DEST="tags/${FULL_VERSION}-candidate"
DEST_DIR="${DIST_DIR}/${PROJECT}-${FULL_VERSION}-candidate"

# find out which CVEs are ready and will be reporting in this candidate
calc_ready_CVE_DIRS "${DIST_DIR}/pmc"

# if a directory of the candidate already exists at pmc/SECURITY
# something is fishy and we require someone to decide what to fix.
if test -d "${DIST_DIR}/pmc/SECURITY/${PROJECT}-${FULL_VERSION}"; then
  cat <<EOF >&2
${DIST_DIR}/pmc/SECURITY/${PROJECT}-${FULL_VERSION} already exists.
This indicates that the candidate has already been built before
and not been fully removed again. Please verify if the version
number used is correct or if the removal of SECURITY/${PROJECT}-${FULL_VERSION}
was just omitted by mistake.
EOF
  fail "Please correct this and try again."
fi

cat <<EOF
creating release candidate:
  PROJECT: $PROJECT
  VERSION: $FULL_VERSION
  URL: $SVN_URL
  SOURCE: $SVN_SRC@$SVN_REV
  DEST: $SVN_DEST
  LOCAL: $DEST_DIR
  CVEs: ${CVE_DIRS:-none}
EOF
if ! ask_yes_no "Is this as expected?"; then
  exit 1
fi

if svn ls "$SVN_BASE/$SVN_DEST" >/dev/null 2>&1; then
  warn "release candidate tag already exists at $SVN_DEST"
  if ! ask_yes_no "Do you want to continue anyway?"; then
    exit 1
  fi
else
  echo "creating candidate tag: $SVN_DEST"
  svn cp -m "Tag $SVN_SRC@$SVN_REV as $FULL_VERSION" "$SVN_BASE/$SVN_SRC@$SVN_REV" "$SVN_BASE/$SVN_DEST"
  rm -rf "$DEST_DIR"
fi

if test ! -d "$DEST_DIR"; then
  mkdir -p `dirname "$DEST_DIR"`
  echo "checkout $DEST_DIR"
  svn checkout -q "$SVN_BASE/$SVN_DEST" "$DEST_DIR"
else
  echo "updating existing checkout in $DEST_DIR"
  svn update "$DEST_DIR"
fi

pushd "$DEST_DIR" >/dev/null

if test -f include/apr_version.h; then
  echo "setting APR_IS_DEV_VERSION to undef"
  perl -pi -e 's@^#define APR_IS_DEV_VERSION@/* #undef APR_IS_DEV_VERSION */@' include/apr_version.h
  if grep -e '^#define APR_IS_DEV_VERSION' include/apr_version.h >/dev/null 2>&1;then
    fail "implementing change to undef APR_IS_DEV_VERSION failed"
  fi
fi

if test -f include/apu_version.h; then
  echo "setting APU_IS_DEV_VERSION"
  perl -pi -e 's@^#define APU_IS_DEV_VERSION@/* #undef APU_IS_DEV_VERSION */@' include/apu_version.h
  if grep -e '^#define APU_IS_DEV_VERSION' include/apu_version.h >/dev/null 2>&1;then
    fail "implementing change to undef APU_IS_DEV_VERSION failed"
  fi
fi


# Ensure the Copyright date reflects the current year
for src in NOTICE include/apr_version.h; do
  current_year=`date +%Y`
  if test -f "$src"; then
      perl -pi -e "s/\d+ The Apache Software/$current_year The Apache Software/g" "$src"
  fi
done

popd >/dev/null

echo "changes for ${PROJECT}-${FULL_VERSION} in ${DEST_DIR}"
svn stat "${DEST_DIR}"
echo ""
if ask_yes_no "Do you want to commit these?"; then
  svn commit -m "Post $FULL_VERSION tag updates" "$DEST_DIR"
  echo "release candidate sources created in $SVN_DEST"
  save_version

  if test -n "${CVE_DIRS}"; then
    echo "Saving CVE information for ${PROJECT}-${FULL_VERSION}"
    mkdir "${DIST_DIR}/pmc/SECURITY/${PROJECT}-${FULL_VERSION}"
    pushd "${DIST_DIR}/pmc/SECURITY/${PROJECT}-${FULL_VERSION}"
    for CVE in $CVE_DIRS; do
      ln -s ../"${CVE}" "${CVE}"
    done
    popd
    svn add "${DIST_DIR}/pmc/SECURITY/${PROJECT}-${FULL_VERSION}"
    if ask_yes_no "Do you want to commit these?"; then
      svn commit -m "CVEs included in ${PROJECT}-${FULL_VERSION}" "${DIST_DIR}/pmc"
    fi
  fi
fi
