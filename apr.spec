
%define aprver 0

Summary: Apache Portable Runtime library
Name: apr
Version: 0.9.4
Release: 22
License: Apache Software License
Group: System Environment/Libraries
URL: http://apr.apache.org/
Source0: %{name}-%{version}.tar.gz
Patch0: apr-0.9.3-deplibs.patch
Patch1: apr-0.9.3-config.patch
Patch2: apr-0.9.3-testrand.patch
Patch3: apr-0.9.3-noipv6.patch
Patch4: apr-0.9.4-trimlibs.patch
Patch5: apr-0.9.4-pthread.patch
Patch6: apr-0.9.4-tests.patch
Patch7: apr-0.9.4-tempdir.patch
Patch8: apr-0.9.4-aprofft.patch
Patch9: apr-0.9.4-dotdot.patch
Patch10: apr-0.9.4-cflags.patch
Patch11: apr-0.9.4-mmapzero.patch
Patch12: apr-0.9.4-largefile.patch
Patch13: apr-0.9.4-largecopy.patch
Patch14: apr-0.9.4-gniv4map.patch
Patch15: apr-0.9.4-time2038.patch
Patch16: apr-0.9.4-mutextype.patch
Patch17: apr-0.9.4-permbits.patch
Patch18: apr-0.9.4-stacksize.patch
Patch19: apr-0.9.4-cleanups.patch
Patch20: apr-0.9.4-nested.patch
Patch21: apr-0.9.4-lp64psem.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
BuildPrereq: autoconf, libtool, doxygen
Conflicts: subversion < 0.20.1-2

%description
The mission of the Apache Portable Runtime (APR) is to provide a
free library of C data structures and routines, forming a system
portability layer to as many operating systems as possible,
including Unices, MS Win32, BeOS and OS/2.

%package devel
Group: Development/Libraries
Summary: APR library development kit
Requires: apr = %{version}
Conflicts: subversion-devel < 0.20.1-2

%description devel
This package provides the support files which can be used to 
build applications using the APR library.  The mission of the
Apache Portable Runtime (APR) is to provide a free library of 
C data structures and routines.

%prep
%setup -q
%patch0 -p1 -b .deplibs
%patch1 -p1 -b .config
%patch2 -p1 -b .testrand
%patch3 -p1 -b .noipv6
%patch4 -p1 -b .trimlibs
%patch5 -p1 -b .pthread
%patch6 -p1 -b .tests
%patch7 -p1 -b .tempdir
%patch8 -p1 -b .aprofft
%patch9 -p1 -b .dotdot
%patch10 -p1 -b .cflags
%patch11 -p1 -b .mmapzero
%patch12 -p1 -b .largefile
%patch13 -p1 -b .largecopy
%patch14 -p1 -b .gniv4map
%patch15 -p1 -b .time2038
%patch16 -p1 -b .mutextype
%patch17 -p1 -b .permbits
%patch18 -p1 -b .stacksize
%patch19 -p1 -b .cleanups
%patch20 -p1 -b .nested
%patch21 -p1 -b .lp64psem

%build
# regenerate configure script etc.
./buildconf
%configure \
        --includedir=%{_includedir}/apr-%{aprver} \
        --with-installbuilddir=%{_libdir}/apr/build \
        --with-devrandom=/dev/urandom \
        CC=gcc CXX=g++
make %{?_smp_mflags} CFLAGS=-Wall && make dox

%check
# Run non-interactive tests
%ifarch x86_64
# https://bugzilla.redhat.com/bugzilla/show_bug.cgi?id=97611
excludes=testlock
%endif
pushd test
make %{?_smp_mflags} testall CFLAGS=-fno-strict-aliasing
TZ=PST8PDT ./testall -v ${excludes+-x $excludes} || exit 1
popd

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

# These are referenced by apr_rules.mk
for f in make_exports.awk make_var_export.awk; do
    install -m 644 build/${f} $RPM_BUILD_ROOT%{_libdir}/apr/build/${f}
done

install -m 755 build/mkdir.sh $RPM_BUILD_ROOT%{_libdir}/apr/build/mkdir.sh

# Sanitize apr_rules.mk
sed -e "/^apr_build/d" \
    -e 's|$(apr_builders)|%{_libdir}/apr/build|g' \
    -e 's|$(apr_builddir)|%{_libdir}/apr/build|g' \
    < build/apr_rules.mk > $RPM_BUILD_ROOT%{_libdir}/apr/build/apr_rules.mk

# Move docs to more convenient location
mv docs/dox/html html

# Unpackaged files:
rm -f $RPM_BUILD_ROOT%{_libdir}/apr.exp

%clean
rm -rf $RPM_BUILD_ROOT

%post -p /sbin/ldconfig

%postun -p /sbin/ldconfig

%files
%defattr(-,root,root,-)
%doc CHANGES LICENSE
%{_libdir}/libapr-%{aprver}.so.*

%files devel
%defattr(-,root,root,-)
%doc docs/APRDesign.html docs/canonical_filenames.html
%doc docs/incomplete_types docs/non_apr_programs
%doc --parents html
%{_bindir}/apr-config
%{_libdir}/libapr-%{aprver}.*a
%{_libdir}/libapr-%{aprver}.so
%dir %{_libdir}/apr
%dir %{_libdir}/apr/build
%{_libdir}/apr/build/*
%dir %{_includedir}/apr-%{aprver}
%{_includedir}/apr-%{aprver}/*.h

%changelog
* Tue Aug 31 2004 Joe Orton <jorton@redhat.com> 0.9.4-22
- backport fixes from HEAD:
 * correct implementation of nested mutexes
 * support for POSIX semaphores on LP64 platforms

* Thu Jul 15 2004 Joe Orton <jorton@redhat.com> 0.9.4-21
- rebuild for another attempt at using sem_open

* Tue Jul 13 2004 Joe Orton <jorton@redhat.com> 0.9.4-20
- move sticky/suid bits outside APR_OS_DEFAULT bitmask (Greg Hudson)

* Thu Jul  1 2004 Joe Orton <jorton@redhat.com> 0.9.4-19
- rebuild

* Wed Jun 30 2004 Joe Orton <jorton@redhat.com> 0.9.4-18
- rebuild now /dev/shm is mounted

* Thu Jun 17 2004 Joe Orton <jorton@redhat.com> 0.9.4-17
- add fix for cleanup structure reuse (part of upstream #23567)

* Tue Jun 15 2004 Elliot Lee <sopwith@redhat.com>
- rebuilt

* Thu Jun 10 2004 Joe Orton <jorton@redhat.com> 0.9.4-15
- add support for setuid/setgid/sticky bits (André Malo)
- add apr_threadattr_{guardsize,stacksize}_set() (latter by Jeff Trawick)

* Mon Jun  7 2004 Joe Orton <jorton@redhat.com> 0.9.4-14
- enable posixsem and process-shared pthread mutex support, but
  ensure that sysvsem remains the default mechanism

* Mon May 24 2004 Joe Orton <jorton@redhat.com> 0.9.4-13
- entirely remove 2Gb file size limit from apr_file_copy();
  fixes "svnadmin hotcopy" on repos with >2Gb strings table
- work around getnameinfo bugs with v4-mapped addresses
- fix apr_time_exp_get() for dates in 2038 (Philip Martin)

* Thu May 13 2004 Joe Orton <jorton@redhat.com> 0.9.4-12
- use APR_LARGEFILE in apr_file_{copy,append}

* Wed Mar 24 2004 Joe Orton <jorton@redhat.com> 0.9.4-11
- add APR_LARGEFILE flag

* Mon Mar 15 2004 Joe Orton <jorton@redhat.com> 0.9.4-10
- fix configure check for mmap of /dev/zero
- just put -D_GNU_SOURCE in CPPFLAGS not _{BSD,SVID,XOPEN}_SOURCE

* Tue Mar 02 2004 Elliot Lee <sopwith@redhat.com> 0.9.4-9.1
- rebuilt

* Thu Feb 19 2004 Joe Orton <jorton@redhat.com> 0.9.4-9
- undocument apr_dir_read() ordering constraint and fix tests

* Sun Feb 15 2004 Joe Orton <jorton@redhat.com> 0.9.4-8
- rebuilt without -Wall -Werror

* Fri Feb 13 2004 Elliot Lee <sopwith@redhat.com> 0.9.4-7
- rebuilt

* Tue Feb  3 2004 Joe Orton <jorton@redhat.com> 0.9.4-6
- define apr_off_t as int/long/... to prevent it changing
  with _FILE_OFFSET_BITS on 32-bit platforms

* Mon Jan 12 2004 Joe Orton <jorton@redhat.com> 0.9.4-5
- add apr_temp_dir_get fixes from HEAD

* Thu Jan  8 2004 Joe Orton <jorton@redhat.com> 0.9.4-4
- ensure that libapr is linked against libpthread
- don't link libapr against -lnsl

* Thu Nov 13 2003 Joe Orton <jorton@redhat.com> 0.9.4-3
- -devel package no longer requires libtool

* Fri Oct  3 2003 Joe Orton <jorton@redhat.com> 0.9.4-2
- disable tests on x86_64 (#97611)

* Fri Oct  3 2003 Joe Orton <jorton@redhat.com> 0.9.4-1
- update to 0.9.4, enable tests
- ensure that libresolv is not used

* Sun Sep  7 2003 Joe Orton <jorton@redhat.com> 0.9.3-14
- use /dev/urandom (#103049)

* Thu Jul 24 2003 Joe Orton <jorton@redhat.com> 0.9.3-13
- add back CC=gcc, CXX=g++

* Tue Jul 22 2003 Nalin Dahyabhai <nalin@redhat.com> 0.9.3-12
- rebuild

* Mon Jul 14 2003 Joe Orton <jorton@redhat.com> 0.9.3-11
- work round useless autoconf 2.57 AC_DECL_SYS_SIGLIST

* Thu Jul 10 2003 Joe Orton <jorton@redhat.com> 0.9.3-10
- support --cc and --cpp arguments in apr-config

* Thu Jul  3 2003 Joe Orton <jorton@redhat.com> 0.9.3-9
- force libtool to use CC=gcc, CXX=g++

* Thu Jul  3 2003 Joe Orton <jorton@redhat.com> 0.9.3-8
- fix libtool location in apr_rules.mk

* Mon Jun 30 2003 Joe Orton <jorton@redhat.com> 0.9.3-7
- use AI_ADDRCONFIG in getaddrinfo() support (#73350)
- include a working libtool script rather than relying on
 /usr/bin/libtool (#97695)

* Wed Jun 18 2003 Joe Orton <jorton@redhat.com> 0.9.3-6
- don't use /usr/bin/libtool

* Wed Jun 04 2003 Elliot Lee <sopwith@redhat.com>
- rebuilt

* Tue May 20 2003 Joe Orton <jorton@redhat.com> 0.9.3-5
- add fix for psprintf memory corruption (CAN-2003-0245)
- remove executable bit from apr_poll.h

* Thu May  1 2003 Joe Orton <jorton@redhat.com> 0.9.3-4
- link libapr against libpthread
- make apr-devel conflict with old subversion-devel
- fix License

* Tue Apr 29 2003 Joe Orton <jorton@redhat.com> 0.9.3-3
- run ldconfig in post/postun

* Tue Apr 29 2003 Joe Orton <jorton@redhat.com> 0.9.3-2
- patch test suite to not care if IPv6 is disabled

* Mon Apr 28 2003 Joe Orton <jorton@redhat.com> 0.9.3-1
- initial build
