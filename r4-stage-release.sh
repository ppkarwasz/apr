#!/bin/sh

# Publish a staged release to the world (website)
#
# USAGE: r4-stage-release.sh [version]
# version: x.y.z (example 2.4.38)

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  prepare website and local checkouts for changes including removal of previous release
  Does not commit anything, just prepares.
  If no version is given, the current version in the checkout is used.
  Arguments:
    version        as 'm.n.p(-suffix)?', the version to use.
  Options:
    -h             print usage information
    -n             dry run, do not exit on failures
    -y             never ask, always assume yes
EOF
  exit 1
}

fail_not_dry() {
  if test -z "${DRY_RUN}"; then
    fail "$@"
  fi
  echo "IGNORED ERROR: $@"
}

fake_changes() {
  changes="$1"
  cat <<EOF > "${changes}"
                                                         -*- coding: utf-8 -*-
Changes with Apache ${VERSION}

EOF
}

DRY_RUN=""
while getopts "hny" opt; do
    case $opt in
        h)  usage
            ;;
        n)  DRY_RUN="1"
            ;;
        y)  ALWAYS_YES=1
            ;;
    esac
done
shift $((OPTIND-1))

source `dirname $0`/common-lib.sh
source `dirname $0`/env.sh

detect_checkout

# The dist/ dir should still be there from prior steps.
assure_clean_checkout_sans_dist

detect_version $1

SVN_RELEASE="tags/${VERSION}"

svn ls "$SVN_BASE/$SVN_RELEASE" >/dev/null 2>&1 ||
  fail_not_dry "release does not exist in SVN: $SVN_RELEASE"

AO_DIST_PATH="dist/apache.org-dist"
AO_DIST_RELEASE_PATH="${AO_DIST_PATH}/release/${PROJECT}"

DIST_SITEPATH="${DIST_DIR}/site"

TAR_BASENAME="${PROJECT}-${VERSION}"



test -d "${AO_DIST_PATH}" ||
  fail "dist.apache.org checkout not in working dir ${AO_DIST_PATH} from prior stage"

# we should only keep one release in our dist repository,
# remove the previous one if it exists
prev_patch=`expr ${v_patch} - 1`
PREV_VERSION="${v_major}.${v_minor}.${prev_patch}"
for i in "${AO_DIST_RELEASE_PATH}/${PROJECT}-${PREV_VERSION}".*; do
  test -f "$i" && svn rm "$i"
done

########################################
# checkout and patch the project website
rm -rf "${DIST_SITEPATH}"
svn co ${SVN_SITE_URL} "${DIST_SITEPATH}"

if [ $is_apr -eq 1 ]; then
    PROJNAME=APR
    # followed immediately by version
    HTML_REGEX="APR |apr-|Apache Portable Runtime "
else
    PROJNAME=APR-util
    # followed immediately by version
    HTML_REGEX="APR-util |apr-util-|Apache Portable Runtime Utility "
fi
#Update the site content with the new release date and version
# XXX: doap.rdf has to be done manually for now
echo "updating site content for ${PROJECT}-${VERSION}"

date_string=`date '+%B %d, %Y'`
#Modify the home page by replacing the date and the version string
perl -pi -e "s/($HTML_REGEX)${v_major}\.${v_minor}\.\d+/\${1}${VERSION}/g" "${DIST_SITEPATH}/xdocs/download.xml" "${DIST_SITEPATH}/xdocs/index.xml"
perl -pi -e "s/${v_major}\.${v_minor}\.\d+ of the ($HTML_REGEX)/${VERSION} of the \$1/g" "${DIST_SITEPATH}/xdocs/download.xml" "${DIST_SITEPATH}/xdocs/index.xml"
perl -pi -e "s/${VERSION}, released [^<]+/${VERSION}, released ${date_string}/" "${DIST_SITEPATH}/xdocs/index.xml"
(cd ${DIST_SITEPATH} && ./build.sh)


echo "adding src tree changes"
stage_checkout_release

# checkout/update pmc and get dir dir names that have
# been recorded there for this release
get_version_CVE_DIRS "${DIST_DIR}/pmc"
if test -n "${CVE_DIRS}"; then
  echo "adding CVEs: ${CVE_DIRS}"
  for changes_file in CHANGES \
    "${AO_DIST_RELEASE_PATH}/${CHANGES}"; do
    for CVE in $CVE_DIRS; do
      add_changes_entry "$changes_file" "${DIST_DIR}/pmc/SECURITY/${CVE}/CVE.json"
    done
  done
fi

echo
echo "PENDING REPOSITORY CHANGES"
echo "--------"
echo "SVN changes staged for ${SVN_DIST_URL}"
svn stat "${AO_DIST_RELEASE_PATH}"
svn diff "${AO_DIST_RELEASE_PATH}/CHANGES*"
echo "--------"
echo "svn changes staged in ${DIST_SITEPATH}"
(cd "${DIST_SITEPATH}" && svn stat)
echo "--------"
echo "SVN changes staged in local checkout for ${SVN_URL}"
svn stat

save_version
