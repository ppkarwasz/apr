#!/bin/sh
#
# release.sh : build a release tarball
#
# USAGE: release.sh PROJECT TAG [SIGNING-USER] [APR-SOURCE]
#
#   The project is either 'apr', 'apr-util' or 'apr-iconv'
#
#   The TAG is the CVS tag that will be pulled when retreiving the source.
#
#   The RELEASE-VERSION is the name that will be given to the tarball.
#   Eg. if RELEASE-VERSION is 5.6.7 then the tarball will be apr-5.6.7.tar.gz
#
#   The SIGNING-USER is an optional name of the key that you'll be signing the
#   release with.
#
#   The APR-SOURCE is an optional path to the local APR source directory 
#   required for apr-util's buildconf to find the required files.
#
#
#   This script will run the appropriate commands to prepare and construct the
#   tarball. The subdirectory will be cleaned up upon exit.
#

if test "$#" != 2 && test "$#" != 3 && test "$#" != 4; then
  echo "USAGE: $0 PROJECT TAG [SIGNING-USER] [APR-SOURCE]" >&2
  echo "  see the comments in this script for more info."      >&2
  exit 1
fi

# This forces all exported releases to be on the same timezone
# when SVN props are used inside files.
TZ=UTC

PROJECT=$1
TAG=$2
SIGNING_USER=$3
APR_SOURCE=$4

case "$PROJECT" in
  apr)
    repos_name="apr"
    ver_prefix="apr"
    ;;
  apr-util)
    repos_name="apr-util"
    ver_prefix="apu"
    ;;
  apr-iconv)
    repos_name="apr-iconv"
    ver_prefix="api"
    ;;
  *)
    echo "ERROR: '$PROJECT' is an unknown project." >&2
    echo "  choose one of: apr, apr-util, apr-iconv"     >&2
    exit 1
esac

dirname="${repos_name}-${TAG}"

echo "       Tag name: $TAG"
echo "      Directory: $dirname"

if test -d ${dirname}; then
  echo "ERROR: for safety, you must manually remove $dirname." >&2
  exit 1
fi

if test -d ${dirname}-win32; then
  echo "ERROR: for safety, you must manually remove ${dirname}-win32." >&2
  exit 1
fi

split="---------------------------------------------------------------------"

# make sure that the perms are good for the tarball
umask 022

echo $split
echo ""
echo "Starting SVN export of ${repos_name} to $dirname ..."
echo ""

svn export http://svn.apache.org/repos/asf/apr/${repos_name}/tags/${TAG} \
           ${dirname}
echo $split
echo ""
echo "Starting SVN export of ${repos_name} to ${dirname}-win32 ..."
echo ""
svn export --native-eol CRLF \
           http://svn.apache.org/repos/asf/apr/${repos_name}/tags/${TAG} \
           ${dirname}-win32

echo $split
echo ""

echo "Eliminating unwanted files (e.g. .cvsignore) and generating initial"
echo "files via buildconf ..."
echo ""

find $dirname -name .cvsignore | xargs rm -f
find $dirname -name autom4te.cache | xargs rm -rf
rm -f $dirname/STATUS
find ${dirname}-win32 -name .cvsignore | xargs rm -f
find ${dirname}-win32 -name autom4te.cache | xargs rm -rf
rm -f ${dirname}-win32/STATUS

if test -n "$APR_SOURCE"; then
  ARGS="--with-apr=$APR_SOURCE"
else
  ARGS=""
fi

if test -x ${dirname}/buildconf; then
    (cd ${dirname} && ./buildconf $ARGS) || exit 1
elif test -x ${dirname}/buildconf.sh; then
    (cd ${dirname} && ./buildconf.sh $ARGS) || exit 1
else
    echo "Unable to find buildconf or buildconf.sh to run."
    exit 1
fi

echo $split
echo ""
echo "Building the tarball, .gz and .bz2 files ..."
echo ""

tar cf ${dirname}.tar ${dirname}
gzip -9 --to-stdout ${dirname}.tar > ${dirname}.tar.gz
bzip2 -9 -c ${dirname}.tar > ${dirname}.tar.bz2
rm ${dirname}.tar

echo $split
echo ""
echo "Building the windows zip file ..."
echo ""
mv ${dirname} ${dirname}-unix
mv ${dirname}-win32 ${dirname}
zip -9 -r ${dirname}-win32-src.zip ${dirname}
mv ${dirname} ${dirname}-win32
mv ${dirname}-unix ${dirname}


echo $split
echo ""
echo "Generating MD5/SHA1 checksum files ..."
echo ""

# check for executables
gpg="`which gpg 2> /dev/null | head -1`"
pgp="`which pgp 2> /dev/null | head -1`"
openssl="`which openssl 2> /dev/null | head -1`"
md5sum="`which md5sum 2> /dev/null | head -1`"
sha1sum="`which sha1sum 2> /dev/null | head -1`"
md5="`which md5 2> /dev/null | head -1`"
sha1="`which sha1 2> /dev/null | head -1`"

set -- ${dirname}.tar.gz ${dirname}.tar.bz2 ${dirname}-win32-src.zip
# if found we use openssl for generating the checksums
if test -x "${openssl}"; then
  for file; do
    if test -f "${file}"; then
      echo "openssl: creating md5 checksum file for ${file} ..."
      ${openssl} md5 -r ${file} > ${file}.md5
      echo "openssl: creating sha1 checksum file for ${file} ..."
      ${openssl} sha1 -r ${file} > ${file}.sha1
      echo "openssl: creating sha256 checksum file for ${file} ..."
      ${openssl} sha256 -r ${file} > ${file}.sha256
      echo "openssl: creating sha512 checksum file for ${file} ..."
      ${openssl} sha512 -r ${file} > ${file}.sha512
    fi
  done
# no openssl found - check if we have gpg
elif test -x "${gpg}"; then
  for file; do
    if test -f "${file}"; then
      echo "gpg: creating md5 checksum file for ${file} ..."
      ${gpg} --print-md md5 ${file} |\
          sed -e '{N;s#\n##;}' |\
          sed -e 's#\(.*\): \(.*\)#\2::\1#;s#[\r\n]##g;s# ##g' \
              -e 'y#ABCDEF#abcdef#;s#::# *#' > ${file}.md5
      echo "gpg: creating sha1 checksum file for ${file} ..."
      ${gpg} --print-md sha1 ${file} |\
          sed -e '{N;s#\n##;}' |\
          sed -e 's#\(.*\): \(.*\)#\2::\1#;s#[\r\n]##g;s# ##g' \
              -e 'y#ABCDEF#abcdef#;s#::# *#' > ${file}.sha1
    fi
  done
else
  # no openssl or gpg found - check for md5sum
  if test -x "${md5sum}"; then
    for file; do
      if test -f "${file}"; then
        echo "md5sum: creating md5 checksum file for ${file} ..."
        ${md5sum} -b ${file} > ${file}.md5
      fi
    done
  # no openssl or gpg found - check for md5
  elif test -x "${md5}"; then
    for file; do
      if test -f "${file}"; then
        echo "md5: creating md5 checksum file for ${file} ..."
        ${md5} -r ${file} | sed -e 's# # *#' > ${file}.md5
      fi
    done
  fi
  # no openssl or gpg found - check for sha1sum
  if test -x "${sha1sum}"; then
    for file; do
      if test -f "${file}"; then
        echo "sha1sum: creating sha1 checksum file for ${file} ..."
        ${sha1sum} -b ${file} > ${file}.sha1
      fi
    done
  # no openssl or gpg found - check for sha1
  elif test -x "${sha1}"; then
    for file; do
      if test -f "${file}"; then
        echo "sha1: creating sha1 checksum file for ${file} ..."
        ${sha1} -r ${file} | sed -e 's# # *#' > ${file}.sha1
      fi
    done
  fi
fi

echo $split
echo ""
echo "Cleaning up and signing the files ..."
echo ""

rm -rf ${dirname}
rm -rf ${dirname}-win32

# if found we use pgp for signing the files
if test -x "${pgp}"; then
  if test -n "${SIGNING_USER}"; then
    args="-u ${SIGNING_USER}"
  fi
  for file; do
    if test -f "${file}"; then
      echo "pgp: creating asc signature file for ${file} ..."
      ${pgp} -sba ${file} ${args}
    fi
  done
# no pgp found - check for gpg
elif test -x "${gpg}"; then
  if test -n "${SIGNING_USER}"; then
    args="--default-key ${SIGNING_USER}"
  fi
  for file; do
    if test -f "${file}"; then
      echo "gpg: creating asc signature file for ${file} ..."
      ${gpg} --armor ${args} --detach-sign ${file}
    fi
  done
else
  echo "PGP or GnuPG not found!  Not signing release!"
fi
