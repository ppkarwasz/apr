#!/bin/sh
#
# release.sh : build a release tarball
#
# USAGE: release.sh PROJECT VERSION [SIGNING-USER] [APR-SOURCE]
#
#   The project is either 'apr', 'apr-util' or 'apr-iconv'
#
#   The version number is specified as MAJOR.MINOR.PATCH (and will be used
#   in the output tarball name). The script will then look for a CVS tag
#   named "APR_{MAJOR}_{MINOR}_{PATCH}" and export it into a subdirectory
#   (of the current directory). Next, it will run the appropriate commands
#   to prepare and construct the tarball. The subdirectory will be cleaned
#   up upon exit.
#
#   The "signing user" is the name of the key that you'll be signing the
#   release with.
#
#   The 'apr source' is a path to the local APR source directory required
#   for apr-util's buildconf to find the required files.
#

if test "$#" != 2 && test "$#" != 3 && test "$#" != 4; then
  echo "USAGE: $0 PROJECT VERSION [SIGNING-USER] [APR-SOURCE]" >&2
  echo "  see the comments in this script for more info."      >&2
  exit 1
fi

case "$1" in
  apr)
    repos_name="apr"
    tag_prefix="APR"
    ver_prefix="apr"
    ;;
  apr-util)
    repos_name="apr-util"
    tag_prefix="APU"
    ver_prefix="apu"
    ;;
  apr-iconv)
    repos_name="apr-iconv"
    tag_prefix="API"
    ver_prefix="api"
    ;;
  *)
    echo "ERROR: '$1' is an unknown project." >&2
    echo "  choose one of: apr, apr-util, apr-iconv"     >&2
    exit 1
esac

vsn="$2"
major="`echo $vsn | sed 's/\..*$//'`"
minor="`echo $vsn | sed 's/^[0-9]*\.\([0-9]*\)\..*$/\1/'`"
patch="`echo $vsn | sed 's/^.*\.//'`"

tagname="${tag_prefix}_${major}_${minor}_${patch}"

dirname="${repos_name}-$vsn"

echo "  Version: $vsn"
echo " Tag name: $tagname"
echo "Directory: $dirname"

if test -d ${dirname}; then
  echo "ERROR: for safety, you must manually remove $dirname." >&2
  exit 1
fi

split="---------------------------------------------------------------------"

# make sure that the perms are good for the tarball
umask 022

echo $split
echo ""
echo "Starting CVS export of ${repos_name} to $dirname ..."
echo ""

cvs -d :pserver:anoncvs@cvs.apache.org:/home/cvspublic export -r ${tagname} -d ${dirname} ${repos_name} > /dev/null || exit 1

echo $split
echo ""

if grep "#define.*${tag_prefix}_IS_DEV_VERSION" ${dirname}/include/${ver_prefix}_version.h > /dev/null; then
  echo "ERROR: ${ver_prefix}_version.h still defines a development version." >&2
  echo "       This script can only produce formal releases." >&2
  exit 1
fi

echo "Eliminating unwanted files (e.g. .cvsignore) and generating initial"
echo "files via buildconf ..."
echo ""

find $dirname -name .cvsignore | xargs rm -f
find $dirname -name autom4te.cache | xargs rm -rf
rm -f $dirnme/STATUS

if test -n "$4"; then
  ARGS="--with-apr=$4"
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
compress ${dirname}.tar

echo $split
echo ""
echo "Cleaning up and signing the files ..."
echo ""

rm -rf ${dirname}

if test -x "`which pgp 2> /dev/null`"; then
  if test -n "$3"; then
    user="-u $3"
  fi

  pgp -sba ${dirname}.tar.gz ${user}
  pgp -sba ${dirname}.tar.Z ${user}

  if test -x "`which md5sum 2> /dev/null`"; then
    md5sum ${dirname}.tar.gz > ${dirname}.tar.gz.md5
    md5sum ${dirname}.tar.Z > ${dirname}.tar.Z.md5
  fi
elif test -x "`which gpg 2> /dev/null`"; then
  if test -n "$3"; then
    user="--default-key $3"
  fi

  gpg --armor ${user} --detach-sign ${dirname}.tar.gz
  gpg --armor ${user} --detach-sign ${dirname}.tar.Z

  gpg --print-md md5 ${dirname}.tar.gz > ${dirname}.tar.gz.md5
  gpg --print-md md5 ${dirname}.tar.Z > ${dirname}.tar.Z.md5
else
  echo "PGP or GnuPG not found!  Not signing release!"
fi
