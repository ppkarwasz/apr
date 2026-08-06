#!/bin/sh

# Commit staged release changes to various SVN repositories and the
# project website

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options] [version]
  Commit staged release changes to project distribution, source repositories
  and web site.
  Arguments:
    version        as 'm.n.p(-suffix)?', the version to use.
  Options:
    -h             print usage information
    -u user-id     your apache user-id, e.g 'ylavic'
EOF
  exit 1
}

asf_id="$USER"

while getopts "hu:" opt; do
    case $opt in
        h)  usage
            ;;
        u)  asf_id="$OPTARG"
            ;;
    esac
done
shift $((OPTIND-1))

source `dirname $0`/common-lib.sh
source `dirname $0`/env.sh

detect_checkout
detect_version $1

AO_DIST_PATH="dist/apache.org-dist"
# /apr/ even for apr-util
AO_DIST_RELEASE_PATH="${AO_DIST_PATH}/release/apr"

SVN_SITE_CONTENT_URL="${SVN_SITE_URL}/${PROJECT}/site/trunk/content/"
DIST_SITEPATH="${DIST_DIR}/site"

echo "updating local checkout"
svn up

test -d "${DIST_SITEPATH}" ||
  fail "staged changes for project site not found in ${DIST_SITEPATH}"
test -d "${AO_DIST_RELEASE_PATH}" ||
  fail "staged changes for dist.a.o not found in ${AO_DIST_RELEASE_PATH}"


echo
echo "PENDING REPOSITORY CHANGES"
echo "--------"
echo "SVN changes staged in ${DIST_SITEPATH}"
cd "${DIST_SITEPATH}"
echo "--------"
echo "SVN changes staged in local checkout for ${SVN_URL}"
svn diff
cd -

echo "--------"
echo "SVN changes staged in ${AO_DIST_RELEASE_PATH}"
cd "${AO_DIST_RELEASE_PATH}"
echo "--------"
echo "SVN changes staged in local checkout"
# mostly removed binaries
svn stat
cd -


if ask_yes_no "Do you want to commit these changes?"; then
  echo "WARNING: this is quite irreversible!"
  if ask_yes_no "Do you REALLY want to commit these changes?"; then
    MSG="publishing release ${PROJECT}-${VERSION}"

    # 1. SRC checkout
    # echo nop: svn commit -m "${MSG}" .
    svn commit -m "${MSG}" .

    # 2. site
    # echo "nop: cd ${DIST_SITEPATH}; git commit -m ${MSG}"
    svn commit -m "${MSG}" "${DIST_SITEPATH}"

    # 3. dist/release 
    # echo nop: svn commit -m "${MSG}" .
    svn commit -m "${MSG}" .
    # echo "nop: cd ${AO_DIST_RELEASE_PATH}; git commit -m ${MSG}"
    svn commit -m "${MSG}" "${AO_DIST_RELEASE_PATH}"

    # success exit
    save_version
    exit 0
  fi
fi

# failure exit
exit 1
