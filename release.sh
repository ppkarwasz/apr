#!/bin/sh
#
# release.sh : build a release tarball
#
# USAGE: release.sh VERSION [SIGNING-USER]
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

if test "$#" != 1 && test "$#" != 2; then
  echo "USAGE: $0 VERSION [SIGNING-USER]"
  echo "  see the comments in this script for more info."
  exit 1
fi

vsn="$1"
major="`echo $1 | sed 's/\..*$//'`"
minor="`echo $1 | sed 's/^[0-9]*\.\([0-9]*\)\..*$/\1/'`"
patch="`echo $1 | sed 's/^.*\.//'`"

tagname="APR_${major}_${minor}_${patch}"

dirname="apr-$vsn"

echo "  Version: $vsn"
echo " Tag name: $tagname"
echo "Directory: $dirname"

if test -d ${dirname}; then
  echo "ERROR: for safety, you must manually remove $dirname."
  exit 1
fi

split="---------------------------------------------------------------------"

# make sure that the perms are good for the tarball
umask 022

echo $split
echo ""
echo "Starting CVS export of APR to $dirname ..."
echo ""

cvs -d :pserver:anoncvs@cvs.apache.org:/home/cvspublic export -r ${tagname} -d ${dirname} apr > /dev/null || exit 1

echo $split
echo ""

if grep '#define.*APR_IS_DEV_VERSION' ${dirname}/include/apr_version.h > /dev/null; then
  echo "ERROR: apr_version.h still defines a development version. This"
  echo "       script can only produce formal releases."
  exit 1
fi

echo "Eliminating unwanted files (e.g. .cvsignore) and generating initial"
echo "files via buildconf ..."
echo ""

find $dirname -name .cvsignore | xargs rm -f
find $dirname -name autom4te.cache | xargs rm -rf
rm -f $dirnme/STATUS

(cd ${dirname} && ./buildconf) || exit 1

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

if which pgp > /dev/null 2>&1; then
  if test -n "$2"; then
    user="-u $2"
  fi

  pgp -sba ${dirname}.tar.gz ${user}
  pgp -sba ${dirname}.tar.Z ${user}

  ### md5 summaries?
else
  if test -n "$2"; then
    user="--default-key $2"
  fi

  gpg --armor ${user} --detach-sign ${dirname}.tar.gz
  gpg --armor ${user} --detach-sign ${dirname}.tar.Z

  gpg --print-md md5 ${dirname}.tar.gz > ${dirname}.tar.gz.md5
  gpg --print-md md5 ${dirname}.tar.Z > ${dirname}.tar.Z.md5
fi
