#!/bin/sh
#
# release.sh : build a release tarball
#
# USAGE: release.sh PROJECT TAG RELEASE-VERSION [SIGNING-USER] [APR-SOURCE]
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
#   The APR-SOURCE is an optional path to the local APR source directory required
#   for apr-util's buildconf to find the required files.
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

split="---------------------------------------------------------------------"

# make sure that the perms are good for the tarball
umask 022

echo $split
echo ""
echo "Starting SVN export of ${repos_name} to $dirname ..."
echo ""

#cvs -d :pserver:anoncvs@cvs.apache.org:/home/cvspublic export -r ${TAG} -d ${dirname} ${repos_name} > /dev/null || exit 1
svn export http://svn.apache.org/repos/asf/apr/${repos_name}/tags/${TAG} ${dirname}

echo $split
echo ""

echo "Eliminating unwanted files (e.g. .cvsignore) and generating initial"
echo "files via buildconf ..."
echo ""

find $dirname -name .cvsignore | xargs rm -f
find $dirname -name autom4te.cache | xargs rm -rf
rm -f $dirname/STATUS

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
echo "Building the tarball, .gz, and .Z files ..."
echo ""

tar cf ${dirname}.tar ${dirname}
gzip -9 --to-stdout ${dirname}.tar > ${dirname}.tar.gz
bzip2 -c ${dirname}.tar > ${dirname}.tar.bz2
compress ${dirname}.tar

echo $split
echo ""
echo "Cleaning up and signing the files ..."
echo ""

rm -rf ${dirname}

if test -x "`which pgp 2> /dev/null`"; then
  if test -n "$SIGNING_USER"; then
    user="-u $SIGNING_USER"
  fi

  pgp -sba ${dirname}.tar.gz ${user}
  pgp -sba ${dirname}.tar.bz2 ${user}
  pgp -sba ${dirname}.tar.Z ${user}

  if test -x "`which md5sum 2> /dev/null`"; then
    md5sum ${dirname}.tar.gz > ${dirname}.tar.gz.md5
    md5sum ${dirname}.tar.bz2 > ${dirname}.tar.bz2.md5
    md5sum ${dirname}.tar.Z > ${dirname}.tar.Z.md5
  fi
elif test -x "`which gpg 2> /dev/null`"; then
  if test -n "$SIGNING_USER"; then
    user="--default-key $SIGNING_USER"
  fi

  gpg --armor ${user} --detach-sign ${dirname}.tar.gz
  gpg --armor ${user} --detach-sign ${dirname}.tar.bz2
  gpg --armor ${user} --detach-sign ${dirname}.tar.Z

  gpg --print-md md5 ${dirname}.tar.gz > ${dirname}.tar.gz.md5
  gpg --print-md md5 ${dirname}.tar.bz2 > ${dirname}.tar.bz2.md5
  gpg --print-md md5 ${dirname}.tar.Z > ${dirname}.tar.Z.md5
else
  echo "PGP or GnuPG not found!  Not signing release!"
fi
