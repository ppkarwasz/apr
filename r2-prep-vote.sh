#!/bin/sh

# Take generated tarballs and call vor a vote.

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  publish the release candidate tarballs in the dist SVN. The tars need
  to exist in the local 'dist' directory (created by r1-release.sh).
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

EXP_DIRNAME="${PROJECT}-${VERSION}"
EXP_PATH="${DIST_DIR}/"
# almost the same, except using the full version string
TAR_BASENAME="${PROJECT}-${FULL_VERSION}-candidate"
TAR_PATH="${DIST_DIR}/${TAR_BASENAME}"

test -d "${EXP_PATH}" ||
  fail "export directory ${EXP_PATH} does not exist. Did you run 'r1-release.sh'?"
test -f "${TAR_PATH}.tar.gz" ||
  fail "export tarball ${TAR_PATH}.tar.gz does not exist. Did you run 'r1-release.sh'?"

# never publish a candidate whose signing (silently) failed in r1-release.sh
echo "verifying checksums and signatures in ${DIST_DIR} ..."
verify_dist_files "${TAR_PATH}.tar.gz" "${TAR_PATH}.tar.bz2" "${TAR_PATH}-win32-src.zip"

#Ensure scratch space is in a state we are ready to work with
AO_DIST_PATH="dist/apache.org-dist"
# always apr
AO_DIST_DEV_PATH="${AO_DIST_PATH}/dev/apr"
AO_DIST_RELEASE_PATH="${AO_DIST_PATH}/release/apr"

# SVN repository is huge, carefully check out only what we need
rm -rf "${AO_DIST_PATH}"
echo "checking out dist from ${SVN_DIST_URL} ..."
svn checkout --depth=empty "$SVN_DIST_URL" "${AO_DIST_PATH}" >/dev/null
echo "checking out ${AO_DIST_DEV_PATH} ..."
svn update --set-depth immediates --parents "${AO_DIST_DEV_PATH}" >/dev/null
echo "checking out ${AO_DIST_RELEASE_PATH} ..."
svn update --set-depth immediates --parents "${AO_DIST_RELEASE_PATH}" >/dev/null

# Place the tarballs and add to changeset, remove any existing
# tarballs with same major.minor.patch
echo "adding candidate tars from ${EXP_PATH}*.tar.*"
if ls "${AO_DIST_DEV_PATH}"/${EXP_DIRNAME}.* >/dev/null 2>&1;then
  svn rm "${AO_DIST_DEV_PATH}"/${EXP_DIRNAME}.*
fi
cp "${TAR_PATH}"*.tar.* "${AO_DIST_DEV_PATH}"/
cp "${TAR_PATH}"*.zip* "${AO_DIST_DEV_PATH}"/
svn add "${AO_DIST_DEV_PATH}"/${TAR_BASENAME}*.tar.* "${AO_DIST_DEV_PATH}"/${TAR_BASENAME}*.zip* >/dev/null

cp "${DIST_DIR}/${TAR_BASENAME}"/CHANGES "${AO_DIST_DEV_PATH}"/${CHANGES}-${v_major}.${v_minor}
# maybe already added
svn add "${AO_DIST_DEV_PATH}"/${CHANGES}-${v_major}.${v_minor} >/dev/null 2>/dev/null || true

echo "updating Announcement${v_major}.${v_minor}.*"
#Prep announcement files with latest version
perl -pi -e "s/$v_major\.$v_minor\.\d+ (Released|of the)/$VERSION \1/g" \
  "${AO_DIST_DEV_PATH}"/${ANNOUNCEFILE}.*

#Ensure the right date is in announcement file
release_date=`LC_TIME=en_US date "+%B %d, %Y"`
perl -pi -e "s/^   (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*/   $release_date/"\
  "${AO_DIST_DEV_PATH}"/${ANNOUNCEFILE}.*

#Push changes up to dev
echo "changes ready for commit in ${AO_DIST_DEV_PATH}"
svn stat "${AO_DIST_DEV_PATH}"
svn diff "${AO_DIST_DEV_PATH}"/Announcement1*
if ask_yes_no "Do you want to commit these?"; then
  svn commit -m "Add $FULL_VERSION files" "${AO_DIST_DEV_PATH}"
fi

pushd ${DIST_DIR} > /dev/null
TAR_SIGS=`grep '^' ${TAR_BASENAME}.tar.gz.sha* | sed -e 's/.*.tar.gz.//g' -e 's/:/: /g'`
popd >/dev/null

cat <<EOF > "${DIST_DIR}/mail-vote-$FULL_VERSION.txt"
Subject: [VOTE] Release ${PROJECT}-${FULL_VERSION} as ${PROJECT}-${VERSION}

Hi all,

Please find below the proposed release tarball and signatures:

${SVN_DIST_URL}dev/apr/

I would like to call a VOTE over the next few days to release
this candidate tarball ${PROJECT}-${FULL_VERSION} as $VERSION:
[ ] +1: It's not just good, it's good enough!
[ ] +0: Let's have a talk.
[ ] -1: There's trouble in paradise. Here's what's wrong.

The computed digests of the tarball up for vote are:
${TAR_SIGS}

The SVN candidate source is found at ${SVN_DEST}.
EOF
echo "An announcement email template has been created at ${DIST_DIR}/mail-vote-$FULL_VERSION.txt"
cat "${DIST_DIR}/mail-vote-$FULL_VERSION.txt"

save_version
