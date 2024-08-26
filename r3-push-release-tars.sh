#!/bin/sh

# Stage a release candidate that has passed voting
#
# USAGE: r3-push-release-tars.sh [version]
# version: x.y.z (example 2.4.38)

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  release a candidate that has passed voting. The tars need
  to exist at ${SVN_DIST_URL}/dev/ (put there by push-tars.sh).
  If no version is given, the current version in the checkout is used.
  Arguments:
    version        as 'm.n.p(-suffix)?', the version to use.
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
detect_version $1

SVN_DEST="tags/${FULL_VERSION}-candidate"
SVN_RELEASE="tags/${VERSION}"

svn ls "$SVN_BASE/$SVN_DEST" >/dev/null 2>&1 ||
  fail "release candidate does not exist in SVN: $SVN_DEST"

EXP_DIRNAME="${PROJECT}-${VERSION}"
EXP_PATH="${DIST_DIR}/${EXP_DIRNAME}"
# almost the same, except using the full version string
TAR_BASENAME="${PROJECT}-${FULL_VERSION}"
TAR_PATH="${DIST_DIR}/${TAR_BASENAME}"

#Ensure scratch space is in a state we are ready to work with
AO_DIST_PATH="dist/apache.org-dist"
AO_DIST_DEV_PATH="${AO_DIST_PATH}/dev/${PROJECT}"
AO_DIST_RELEASE_PATH="${AO_DIST_PATH}/release/${PROJECT}"

# SVN repository is huge, carefully check out only what we need
rm -rf "${AO_DIST_PATH}"
echo "checking out dist from ${SVN_DIST_URL} ..."
svn checkout --depth=empty "$SVN_DIST_URL" "${AO_DIST_PATH}" >/dev/null
echo "checking out ${AO_DIST_DEV_PATH} ..."
svn update --set-depth immediates --parents "${AO_DIST_DEV_PATH}" >/dev/null
echo "checking out ${AO_DIST_RELEASE_PATH} ..."
svn update --set-depth immediates --parents "${AO_DIST_RELEASE_PATH}" >/dev/null

if [ -f include/apr_version.h ]; then
    is_apr=1
    ANNOUNCEFILE=Announcement1.x
    CHANGES=CHANGES-APR
else
    is_apr=0
    ANNOUNCEFILE=Announcement-aprutil-1.x
    CHANGES=CHANGES-APR-UTIL
fi

echo "updating ${ANNOUNCEFILE}.*"
#Prep announcement files with latest version
perl -pi -e "s/$v_major\.$v_minor\.\d+ (Released|of the)/$VERSION \1/g" \
  "${AO_DIST_RELEASE_PATH}"/${ANNOUNCEFILE}.*

#Ensure the right date is in announcement file
release_date=`LC_TIME=en_US date "+%B %d, %Y"`
perl -pi -e "s/^   (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*/   $release_date/"\
  "${AO_DIST_RELEASE_PATH}"/${ANNOUNCEFILE}.*

echo "moving voted tars ${AO_DIST_DEV_PATH}/${PROJECT}-${FULL_VERSION}-candidate.tar.*"
#Do an SVN move of the files to retain history
svn mv "${AO_DIST_DEV_PATH}/${PROJECT}-${FULL_VERSION}-candidate".tar.* "${AO_DIST_RELEASE_PATH}"/
svn mv "${AO_DIST_DEV_PATH}/${PROJECT}-${FULL_VERSION}-candidate"*.zip "${AO_DIST_RELEASE_PATH}"/
svn mv "${AO_DIST_DEV_PATH}/${PROJECT}-${FULL_VERSION}-candidate"*.zip.* "${AO_DIST_RELEASE_PATH}"/
if test "${VERSION}" != "${FULL_VERSION}"; then
  # releasing a version with a suffix, e.g. -rc1. rename to just version
  echo "renaming ${FULL_VERSION} files to ${VERSION}"
  for file in "${AO_DIST_RELEASE_PATH}/${PROJECT}-${FULL_VERSION}-candidate".tar.* "${AO_DIST_RELEASE_PATH}/${PROJECT}-${FULL_VERSION}-candidate"*.zip "${AO_DIST_RELEASE_PATH}/${PROJECT}-${FULL_VERSION}-candidate"*.zip.*; do
    dest=`echo $file | sed -e "s/${FULL_VERSION}-candidate/${VERSION}/"`
    svn mv "$file" "$dest"
  done
  # fix the filenames in the hash files (PR65665)
  echo "fixing ${FULL_VERSION} filename to ${VERSION} in hash files"
  for file in "${AO_DIST_RELEASE_PATH}/${PROJECT}-${VERSION}"*.sha*;  do
    perl -pe "s/${FULL_VERSION}-candidate/${VERSION}/" -i $file
  done
fi

cp "${AO_DIST_DEV_PATH}/${CHANGES}-${v_major}.${v_minor}" "${AO_DIST_RELEASE_PATH}"/

echo ""
echo "changes ready for commit in: ${AO_DIST_PATH}"
echo "----------------------------"
svn stat "${AO_DIST_PATH}"
if ask_yes_no "Do you want to commit these?"; then
  svn commit -m "Add release $PROJECT-$VERSION from voted $FULL_VERSION" "${AO_DIST_PATH}"
else
  exit 1
fi

# As a last step, move the candidate tag to the release tag
svn mv -m "release $VERSION from voted $FULL_VERSION" \
  "$SVN_BASE/$SVN_DEST" "$SVN_BASE/$SVN_RELEASE"

save_version
