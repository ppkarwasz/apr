#!/bin/sh -x

#Make sure English is used when formating dates and other things
export LANG=en_US.UTF-8


fail() {
  if test -n "$*"; then
    echo "ERROR: $*" >&2
  fi
  exit 1
}

warn() {
  if test -n "$*"; then
    echo "WARNING: $*" >&2
  fi
  if test "$exit_on_warnings" = 1; then
    exit 1
  fi
}

is_int() {
  x=`expr $1 + 0 2>/dev/null`
  test "$x" = "$1"
}

ask_yes_no() {
  if test "${ALWAYS_YES}" = 1; then
    return 0
  fi
  read -r -p "$* [y/N] " response
  case "$response" in
      [yY][eE][sS]|[yY])
          return 0
          ;;
  esac
  return 1
}

assure_commands() {
  # check that all commands that we need are available
  ok=1
  for cmd in svn git jq sed curl perl awk; do
    if ! type "$cmd" >/dev/null 2>&1; then
      echo "ERROR: needed command not found: $cmd" >&2
      ok=0
    fi
  done
  if test "$ok" != 1; then
    fail "please install the missing components."
  fi
}

# Inspect the local directory and populate
# SVN_URL   the absolute url of the local checkout
# SVN_BASE  the base url of the project
# SVN_SRC   the path relative of SVN_BASE of the checkout
# SVN_REV   the revision of the checkout
detect_checkout() {
  out=`svn stat 2>&1 >/dev/null`
  test -z "$out" || fail "local directory does not seem to be a SVN checkout.\n$out"
  SVN_URL=`svn info --show-item url` || fail "unable to determine SVN url"
  test -n "$SVN_URL" || fail "unable to determine SVN url"
  case "$SVN_URL" in
    */trunk)
      SVN_BASE=`echo $SVN_URL | sed -e 's,/trunk,,'`
      SVN_SRC=trunk
      ;;
    */branches/*)
      SVN_BASE=`echo $SVN_URL | sed -e 's,/branches/.*,,'`
      SVN_SRC=`echo $SVN_URL | sed -e 's,.*/branches/,branches/,'`
      ;;
    *)
      fail "unable to detect path in $SVN_URL"
      ;;
  esac
  SVN_REV=`svn info --show-item revision` || fail "unable to determine SVN revision"
  test -n "$SVN_REV" || fail "unable to determine SVN revision"
  PROJECT=`basename $SVN_BASE`
}

assure_clean_checkout() {
  out=`svn stat`
  test -z "$out" || fail "local checkout is not clean.\n$out"
}
assure_clean_checkout_sans_dist() {
  out=`svn stat|grep -v '?       dist'`||true
  test -z "$out" || fail "local checkout is not clean.\n$out"
}

# given the version input (possibly empty),
# detect/check the version components and set variabels
# VERSION      the version string "major.minor.patch"
# FULL_VERSION $VERSION plus the optional suffix
# v_major      the major integer
# v_minor      the minor integer
# v_patch      the patch integer
# v_suffix     the optional suffix, e.g. 'rc1' or so
detect_version() {
  assure_commands
  version=$1
  case "$version" in
    rc*)
      v_suffix="$version"
      version=""
      ;;
  esac
  if test -z "$version"; then
    # did we record it already?
    if test -f "${DIST_DIR}/VERSION"; then
      source "${DIST_DIR}/VERSION"
    elif test -f include/apr_version.h; then
      # determine version from local files
      v_major=`grep -E '#define\sAPR_MAJOR_VERSION' include/apr_version.h | awk '{print $3}'`
      v_minor=`grep -E '#define\sAPR_MINOR_VERSION' include/apr_version.h | awk '{print $3}'`
      v_patch=`grep -E '#define\sAPR_PATCH_VERSION' include/apr_version.h | awk '{print $3}'`
      ANNOUNCEFILE=Announcement1.x
      CHANGES=CHANGES-APR
      is_apr=1
    elif test -f include/apu_version.h; then
      # determine version from local files
      v_major=`grep -E '#define\sAPU_MAJOR_VERSION' include/apu_version.h | awk '{print $3}'`
      v_minor=`grep -E '#define\sAPU_MINOR_VERSION' include/apu_version.h | awk '{print $3}'`
      v_patch=`grep -E '#define\sAPU_PATCH_VERSION' include/apu_version.h | awk '{print $3}'`
      ANNOUNCEFILE=Announcement-aprutil-1.x
      CHANGES=CHANGES-APR-UTIL
      is_apr=0
    else
      fail "unable to determine version in local checkout"
    fi
  else
    if test -f include/apr_version.h; then
      is_apr=1
    elif test -f include/apu_version.h; then
      is_apr=0
    fi

    v_major=`echo $version | cut -d "." -f 1`
    v_minor=`echo $version | cut -d "." -f 2`
    #Not currently used in this script, but make it available. Support -alpha, -beta -rcX names here
    v_patch=`echo $version | cut -d "." -f 3 | sed -e 's/-.*//'`
    v_suffix=`echo $version | cut -d "." -f 3 | sed -e 's/[^-]*-//'`
    if test "$v_suffix" = "$v_patch"; then
      v_suffix=""
    fi
  fi

  is_int ${v_major} || fail "version major '${v_major}' is not a number"
  is_int ${v_minor} || fail "version minor '${v_minor}' is not a number"
  is_int ${v_patch} || fail "version patch '${v_patch}' is not a number"

  # double check that our checkout matches the version we detected
  if [ $is_apr -eq 1 ]; then
      svn_v_major=`grep -E '#define\sAPR_MAJOR_VERSION' include/apr_version.h | awk '{print $3}'`
      svn_v_minor=`grep -E '#define\sAPR_MINOR_VERSION' include/apr_version.h | awk '{print $3}'`
      if test "$v_major" != "$svn_v_major" -o "$v_minor" != "$svn_v_minor"; then
          fail "detect version ${v_major}.${v_minor} does not match checkout verison ${svn_v_major}.${svn_v_minor}"
      fi
  else
    svn_v_major=`grep -E '#define\sAPU_MAJOR_VERSION' include/apu_version.h | awk '{print $3}'`
    svn_v_minor=`grep -E '#define\sAPU_MINOR_VERSION' include/apu_version.h | awk '{print $3}'`
    if test "$v_major" != "$svn_v_major" -o "$v_minor" != "$svn_v_minor"; then
        fail "detect version ${v_major}.${v_minor} does not match checkout verison ${svn_v_major}.${svn_v_minor}"
    fi
  fi
  VERSION="${v_major}.${v_minor}.${v_patch}"
  FULL_VERSION="${VERSION}"
  if test -n "${v_suffix}"; then
    FULL_VERSION="${VERSION}-${v_suffix}"
  fi
}

save_version() {
  cat <<EOF > "${DIST_DIR}/VERSION"
v_major="${v_major}"
v_minor="${v_minor}"
v_patch="${v_patch}"
v_suffix="${v_suffix}"
is_apr="${is_apr}"
ANNOUNCEFILE="${ANNOUNCEFILE}"
CHANGES="${CHANGES}"
EOF
}

check_autotools() {
  #--------------------------------------------------------------------------
  # autoconf 2.59 or newer
  #
  ac_version=`${AUTOCONF:-autoconf} --version 2>/dev/null|head -1| sed -e 's/^[^0-9]*//' -e 's/[a-z]* *$//'`
  if test -z "$ac_version"; then
    echo "buildcheck: autoconf not found."
    echo "            You need autoconf version 2.59 or newer installed."
    exit 1
  fi
  IFS=.; set $ac_version; IFS=' '
  if test "$1" = "2" -a "$2" -lt "59" || test "$1" -lt "2"; then
    echo "buildcheck: autoconf version $ac_version found."
    echo "            You need autoconf version 2.59 or newer installed."
    echo "            If you have a sufficient autoconf installed, but it"
    echo "            is not named 'autoconf', then try setting the"
    echo "            AUTOCONF environment variable.  (See the INSTALL file"
    echo "            for details.)"
    exit 1
  fi

  echo "check: autoconf version $ac_version (ok)"

  #--------------------------------------------------------------------------
  # autoheader 2.53 or newer
  #
  ah_version=`${AUTOHEADER:-autoheader} --version 2>/dev/null|head -1| sed -e 's/^[^0-9]*//' -e 's/[a-z]* *$//'`
  if test -z "$ah_version"; then
    echo "buildcheck: autoheader not found."
    echo "            You need autoheader version 2.59 or newer installed."
    exit 1
  fi
  IFS=.; set $ah_version; IFS=' '
  if test "$1" = "2" -a "$2" -lt "59" || test "$1" -lt "2"; then
    echo "buildcheck: autoheader version $ah_version found."
    echo "            You need autoheader version 2.59 or newer installed."
    echo "            If you have a sufficient autoheader installed, but it"
    echo "            is not named 'autoheader', then try setting the"
    echo "            AUTOHEADER environment variable.  (See the INSTALL file"
    echo "            for details.)"
    exit 1
  fi

  echo "check: autoheader version $ah_version (ok)"

  #--------------------------------------------------------------------------
  # libtool 1.4.3 or newer
  #
  LIBTOOL_WANTED_MAJOR=1
  LIBTOOL_WANTED_MINOR=5
  LIBTOOL_WANTED_PATCH=10
  LIBTOOL_WANTED_VERSION=1.5.10

  libtool=`which glibtool 2>/dev/null`
  if test ! -x "$libtool"; then
    libtool=`which libtool`
  fi
  lt_pversion=`$libtool --version 2>/dev/null|head -1|sed -e 's/^[^0-9]*//' -e 's/[- ].*//'`

  if test -z "$lt_pversion"; then
    echo "buildcheck: libtool not found."
    echo "            You need libtool version $LIBTOOL_WANTED_VERSION or newer installed"
    exit 1
  fi
  lt_version=`echo $lt_pversion|sed -e 's/\([a-z]*\)$/.\1/'`
  IFS=.; set $lt_version; IFS=' '
  lt_status="good"
  if test "$1" = "$LIBTOOL_WANTED_MAJOR"; then
     if test "$2" -lt "$LIBTOOL_WANTED_MINOR"; then
        lt_status="bad"
     elif test ! "$2" -gt "$LIBTOOL_WANTED_MINOR" -a \
          ! -z "$LIBTOOL_WANTED_PATCH"; then
         if test "$3" -lt "$LIBTOOL_WANTED_PATCH"; then
             lt_status="bad"
         fi
     fi
  fi
  if test $lt_status != "good"; then
    echo "buildcheck: libtool version $lt_pversion found."
    echo "            You need libtool version $LIBTOOL_WANTED_VERSION or newer installed"
    exit 1
  fi

  echo "check: libtool version $lt_pversion (ok)"
}

create_dist_checksums() {
  if ! openssl version >/dev/null; then
    fail "unable to find 'openssl' in path"
  fi
  for path in "$@"; do
    pushd `dirname "$path"` >/dev/null
    file=`basename "$path"`
    echo " - create checksums for ${file}"
    openssl sha256 ${file} | sed -e 's#^SHA256(\(.*\))= \([0-9a-f]*\)$#\2 *\1#' > ${file}.sha256
    openssl sha512 ${file} | sed -e 's#^SHA512(\(.*\))= \([0-9a-f]*\)$#\2 *\1#' > ${file}.sha512
    popd > /dev/null
  done
}

sign_dist_files() {
  signing_user="$1"; shift

  # check for executables
  gpg2="`which gpg2 2> /dev/null | head -1`"
  gpg="`which gpg 2> /dev/null | head -1`"
  pgp="`which pgp 2> /dev/null | head -1`"

  # there are 3 possible ways to sign, check in preference
  if test -x "${gpg2}"; then
    if test -z "${signing_user}"; then
      args="--default-key"
    else
      args="-u ${signing_user}"
    fi
    for file in "$@"; do
      echo " - gpg2: creating asc signature file for ${file} ..."
      ${gpg2} --armor ${args} --detach-sign ${file}
    done
  elif test -x "${gpg}"; then
    args=""
    if test -n "${signing_user}"; then
      args="-u ${signing_useruser}"
    fi
    for file in "$@"; do
      echo " - gpg: creating asc signature file for ${file} ..."
      ${gpg} --armor ${args} --detach-sign ${file}
    done
  elif test -x "${pgp}"; then
    args=""
    if test -n "${signing_user}"; then
      args="-u ${signing_user}"
    fi
    for file in "$@"; do
      echo " - pgp: creating asc signature file for ${file} ..."
      ${pgp} -sba ${file} ${args}
    done
  else
    fail "neither PGP nor GnuPG found! Not signing release!"
  fi
}

export_httpd_srclib() {
  apr_tag="$1"
  apu_tag="$2"
  export_dir="$3"
  test -d "$export_dir" || fail "not a directory: $export_dir"

  if test -z "$apr_tag" -o -z "$apu_tag"; then
    if ! curl --version >/dev/null 2>&1;then
      fail "curl must be available to retrieve the latest apr versions."
    fi

    if test "`echo 'test-1.2.3' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+'`" != "1.2.3";then
      fail "your system must support 'grep -o' to retrieve the latest apr versions."
    fi
  fi

  SVNHOST=svn.apache.org
  download_url="https://apr.apache.org/download.cgi"
  echo "Determining latest APR and APU versions from $download_url..."

  if test -z "$apr_tag"; then
    apr_tag=`curl -s $download_url | grep 'APR [0-9].*is the best available version' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+'`
    if test -z "$apr_tag"; then
      fail "failed to determine latest APR version from $download_url"
    else
      echo "  APR: $apr_tag"
    fi
  fi

  if test -z "$apu_tag"; then
    apu_tag=`curl -s $download_url | grep 'APR-util [0-9].*is the best available version' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+'`
    if test -z "$apu_tag"; then
      fail "failed to determine latest APR version from $download_url"
    else
      echo "  APU: $apu_tag"
    fi
  fi

  echo "Exporting apr-${apr_tag} to ${export_dir}/srclib ..."
  svn export https://${SVNHOST}/repos/asf/apr/apr/tags/${apr_tag} "${export_dir}"/srclib/apr > /dev/null || exit 1
  echo "Exporting apr-util-${apu_tag} to ${export_dir}/srclib ..."
  svn export https://${SVNHOST}/repos/asf/apr/apr-util/tags/${apu_tag} "${export_dir}"/srclib/apr-util > /dev/null || exit 1
}

buildconf_httpd_export() {
  export_dir="$1"
  test -d "$export_dir" || fail "not a directory: $export_dir"
  pushd "${export_dir}" > /dev/null
    find . -name autom4te*.cache | xargs rm -rf
    ./buildconf || fail
    find . -name autom4te*.cache | xargs rm -rf
  popd > /dev/null
}

fixup_httpd_export() {
  export_dir="$1"
  test -d "$export_dir" || fail "not a directory: $export_dir"

  find "${export_dir}" -name STATUS | xargs rm -rf
  if test -f "${export_dir}/modules/ssl/ssl_expr_parse.y"; then
      touch "${export_dir}"/modules/ssl/ssl_expr_parse.c
      touch "${export_dir}"/modules/ssl/ssl_expr_parse.h
      touch "${export_dir}"/modules/ssl/ssl_expr_scan.c
  elif test -f "${export_dir}/server/util_expr_parse.y"; then
      touch "${export_dir}"/server/util_expr_parse.c
      touch "${export_dir}"/server/util_expr_parse.h
      touch "${export_dir}"/server/util_expr_scan.c
  else
      warn "found no expression parser to fix in export!"
  fi
  find "${export_dir}"/docs/manual -name \*.xml -o -name \*.xml.\* | xargs rm -rf
  find "${export_dir}"/docs/manual -name \*.xsl -o -name \*.xsl.\* | xargs rm -rf
}

indent_entry() {
  indent="$1"
  indent="${indent:-  *) }"
  while read line; do
     echo "${indent}${line}"
     indent="     "
  done
}

cve_changes() {
  CVE_JSON="$1"
  test -f "${CVE_JSON}" || fail "cve_changes: ${CVE_JSON} not found"
  CVE_ID=`jq -r .cveMetadata.cveId "${CVE_JSON}"`
  CVE_TITLE=`jq -r .containers.cna.title "${CVE_JSON}"`
  test -n "${CVE_ID}" -a "${CVE_ID}" != "null" || fail "CVE ID missing in ${CVE_JSON}"
  CVE_DESCR=`jq -r '.containers.cna.descriptions[0].value' "${CVE_JSON}"`
  cat << EOF | fold -sw 65 | indent_entry
SECURITY: ${CVE_ID}: ${CVE_TITLE} (cve.mitre.org)
${CVE_DESCR}

EOF
  CVE_CREDIT=`jq -r '.containers.cna.credits[0].value' "${CVE_JSON}"`
  if test -n "${CVE_CREDIT}" -a "${CVE_CREDIT}" != "null"; then
    cat << EOF | fold -sw 65 | indent_entry "     "
Credits: ${CVE_CREDIT}

EOF
  fi
}

add_changes_entry() {
  CHANGES="$1"
  CVE_JSON="$2"
  test -f "${CHANGES}" || fail "add_changes_entry: changes ${CHANGES} not found"

  cp "${CHANGES}" "${CHANGES}.tmp" ;
  cve_changes "${CVE_JSON}" > "${CHANGES}.entry.tmp"
  awk -v fname="${CHANGES}.entry.tmp" \
    'BEGIN{done = 0; active = 0} done == 0 && active == 0 && /^Changes for APR/{
        active = 1; print; next};
      /^( *\*|Changes for APR)/ && active == 1 && done == 0 {
        rec=$0; while(getline<fname) {
          if (! ($0 ~ /^ *$/)){print}
        }
        printf "\n"; print rec; active = 0; done = 1; next
      } //;' "${CHANGES}".tmp > "${CHANGES}"
  rm -f "${CHANGES}".tmp "${CHANGES}.entry.tmp"
}

stage_checkout_release() {
  # make sure we are up-to-date
  svn up
  # calculate the next patch version
  is_int ${v_patch} || fail "version patch '${v_patch}' is not a number"
  next_patch=`expr ${v_patch} + 1`
  NEXT_VERSION="${v_major}.${v_minor}.${next_patch}"
  if [ $is_apr -eq 1 ]; then
    PROJNAME=APR
    PROJHEADER=apr_version.h
  else
    PROJNAME=APR-UTIL
    PROJHEADER=apu_version.h
  fi

  # Add the corresponding version placeholder in CHANGES.
  perl -pi -e "s{(.*coding: utf-8.*)}{\$1\nChanges for ${PROJNAME} ${NEXT_VERSION}\n}" CHANGES
  # Note the tag date in the STATUS file.
  if test -f STATUS; then
    date_string=`date '+%B %d, %Y'`
    perl -pi -e "s/${VERSION}     : in maintenance/${NEXT_VERSION}     : in maintenance\n    ${VERSION}     : released ${date_string}/" STATUS
  fi

  # set the patch number of the next version
  if test -f include/$PROJHEADER; then
    echo "setting patch number in $PROJHEADER"
    perl -pi -e 's/(#define\s+AP[RU]_PATCH_VERSION\s+)\d*/${1}'${next_patch}'/g' include/${PROJHEADER}
    if ! grep -e "^#define *AP[RU]_PATCH_VERSION.*${next_patch}\$" include/${PROJHEADER} >/dev/null 2>&1;then
      fail "setting of PATCH_VERSION did not return expected value of ${next_patch}"
    fi
  fi

  # Ensure the Copyright date reflects the current year
  current_year=`date +%Y`

  # Ensure the Copyright date reflects the current year
  for src in NOTICE include/apr_version.h; do
    if test -f "$src"; then
      perl -pi -e "s/\d+ The Apache Software/$current_year The Apache Software/g" "$src"
    fi
  done
}

checkout_pmc() {
  dest="$1"
  test -n "${SVN_PMC_URL}" || fail "SVN_PMC_URL not set"
  echo "checking out pmc/${PROJECT} as ${dest}"
  rm -rf "${dest}"
  svn checkout "${SVN_PMC_URL}/${PROJECT}" "${dest}" >/dev/null
}

calc_ready_CVE_DIRS() {
  dest="$1"
  checkout_pmc "${dest}"
  pushd "${dest}/SECURITY" >/dev/null
  CVE_SUBDIRS=`./tools/readiness.sh -n | fgrep '[OK]'| awk '{print $2}' | sort `
  popd >/dev/null

  cves_ok=1
  CVE_DIRS=""
  for CVE in $CVE_SUBDIRS; do
    CVE=`basename "${CVE}"`
    if test -f "${dest}/SECURITY/${CVE}/CVE.json"; then
      CVE_DIRS="$CVE_DIRS ${CVE}"
    else
      echo "ERROR: CVE ${CVE} does not have a CVE.json file."
      cves_ok=0
    fi
  done
  if test "${cves_ok}" != 1; then
    fail "Please correct the files mentioned."
  fi
}

get_version_CVE_DIRS() {
  dest="$1"
  checkout_pmc "${dest}"
  cve_version_dir="${dest}/SECURITY/${PROJECT}-${FULL_VERSION}"
  if ! test -d "${cve_version_dir}"; then
    echo "CVE Directory '${cve_version_dir}' does not exist."
    echo "It should have been created and committed during creation of the candidate."
    fail "something is wrong with the state of ${cve_version_dir}"
  fi
  cves_ok=1
  CVE_DIRS=""
  for CVE in "${cve_version_dir}"/*; do
    if ! test -d "${CVE}"; then
      continue
    fi
    CVE=`basename "${CVE}"`
    if test -f "${dest}/SECURITY/${CVE}/CVE.json"; then
      CVE_DIRS="$CVE_DIRS ${CVE}"
    else
      echo "ERROR: CVE ${CVE} does not have a CVE.json file."
      cves_ok=0
    fi
  done
  if test "${cves_ok}" != 1; then
    fail "Please correct the files mentioned."
  fi
}
