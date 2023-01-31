#!/bin/sh

# Announce a committed release to the world. Copied from httpd.
# Note: This is safe to run while debugging as it only creates mail input

#Useful for debugging
#set -x

#Bail when non-zero return codes are encountered
set -e

usage () {
    cat <<EOF 1>&2
usage: $0 [options]
  Announce a committed release to the world.
  Options:
    -h             print usage information
    -u user-id     your apache user-id, e.g 'ylavic'
    -p project (apr, apr-util)
    -v VERSION (1.7.1)
EOF
  exit 1
}

asf_id=""
PROJECT=""
VERSION=""

while getopts "hu:yp:v:" opt; do
    case $opt in
        h)  usage
            ;;
        u)  asf_id="$OPTARG"
            ;;
        p)  PROJECT="$OPTARG"
            ;;
        v)  VERSION="$OPTARG"
            ;;
        y)  ALWAYS_YES=1
            ;;
    esac
done
shift $((OPTIND-1))

source `dirname $0`/common-lib.sh
source `dirname $0`/env.sh

test -n "${asf_id}" || fail "please specify your ASF id as '-u <asf-id>'"
test -n "${PROJECT}" || fail "please specify your apr or apr-util with -p'"
test -n "${VERSION}" || fail "please specify your VERSION with -v'"

v_major=`echo $VERSION| cut -d "." -f 1`
v_minor=`echo $VERSION| cut -d "." -f 2`

PROJECT_SUBJECT="Apache Portable Runtime"
CHANGES_FILE="CHANGES-APR"
case ${PROJECT} in
    apr) ;;
    apr-util) PROJECT_SUBJECT="Apache Portable Runtime Utility"
              CHANGES_FILE="CHANGES-APR-UTIL"
        ;;
    *) echo "Teach me about ${PROJECT}"
       exit 1
       ;;
esac

AO_DIST_PATH="dist/apache.org-dist"
AO_DIST_RELEASE_PATH="${AO_DIST_PATH}/release/apr"

TAR_BASENAME="${PROJECT}-${VERSION}"
ANNOUNCEMENT="Announcement${v_major}.x.txt"
ANNOUNCE_LISTS="announce@apache.org announce@apr.apache.org"

# SVN repository is huge, carefully check out only what we need
rm -rf "${AO_DIST_PATH}"
echo "checking out dist from ${SVN_DIST_URL} ..."
svn checkout --depth=empty "$SVN_DIST_URL" "${AO_DIST_PATH}" >/dev/null
echo "checking out ${AO_DIST_RELEASE_PATH} ..."
svn update --set-depth immediates --parents "${AO_DIST_RELEASE_PATH}" >/dev/null

if ! ls "${AO_DIST_RELEASE_PATH}/${TAR_BASENAME}".* >/dev/null 2>&1; then
  fail "not found: ${AO_DIST_RELEASE_PATH}/${TAR_BASENAME}.*"
fi
if ! test -f "${AO_DIST_RELEASE_PATH}/${CHANGES_FILE}-${v_major}.${v_minor}"; then
  fail "not found: ${AO_DIST_RELEASE_PATH}/${CHANGES_FILE}-${v_major}.${v_minor}"
fi
if ! test -f "${AO_DIST_RELEASE_PATH}/${ANNOUNCEMENT}"; then
  fail "not found: ${AO_DIST_RELEASE_PATH}/${ANNOUNCEMENT}"
fi


DATE=`date '+%a, %d %b %Y %H:%M:%S %z'`
email="${asf_id}@apache.org"

echo "Announcement Emails are being prepared in ${DIST_DIR}/mail_announce_*."
echo "You may use the following commands to send these:"
echo ""
counter=0
for rcpt in ${ANNOUNCE_LISTS}; do
    MID="<`perl -e 'print time . ".";@chars=("A".."Z",0..0);print $chars[rand @chars] for 1..8;'`@apr.apache.org>"
    mail_file="${DIST_DIR}/mail_announce_${VERSION}-${counter}.txt"
    cat <<EOF > "$mail_file"
From: ${asf_id} <$email>
To: $rcpt
Reply-To: dev@apr.apache.org
Subject: [ANNOUNCEMENT] $PROJECT_SUBJECT $VERSION Released
Date: $DATE
Message-ID: $MID

EOF

  cat "${AO_DIST_RELEASE_PATH}/${ANNOUNCEMENT}" >> "${mail_file}"
  cat <<EOF
  curl --url 'smtps://mail-relay.apache.org:465' \\
    --ssl-reqd --mail-from "${email}" \\
    --mail-rcpt "${rcpt}"  --user '${asf_id}' \\
    --upload-file '${mail_file}'

EOF

  counter=`expr $counter + 1`
done


CVES_MENTIONED=`fgrep CVE- dist/apache.org-dist/release/apr/${CHANGES_FILE}-${v_major}-${v_minor}`
if test -n "${CVES_MENTIONED}"; then
  cat << EOF
Then set the following CVEs mentioned to READY on the ASF cveprocess site (and send the emails from the OSS/ASF tab):
${CVES_MENTIONED}
EOF
else
  echo "There seem to be no CVEs mentioned in the ${CHANGES_FILE}-${VERSION} file."
fi
echo "You are done. Open the champagne!"
