
%define aprver 0

Summary: Apache Portable Runtime library
Name: apr
Version: 0.9.4
Release: 2.1
License: Apache Software License
Group: System Environment/Libraries
URL: http://apr.apache.org/
Source0: %{name}-%{version}.tar.gz
Patch0: apr-0.9.3-deplibs.patch
Patch1: apr-0.9.3-config.patch
Patch2: apr-0.9.3-testrand.patch
Patch3: apr-0.9.3-noipv6.patch
Patch4: apr-0.9.4-noresolv.patch
Patch5: apr-0.9.4-tempdir.patch
Patch6: apr-0.9.4-gniv4map.patch
Patch7: apr-0.9.4-cleanups.patch
Patch8: apr-0.9.4-time2038.patch
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
Requires: apr = %{version}, libtool
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
%patch4 -p1 -b .noresolv
%patch5 -p1 -b .tempdir
%patch6 -p1 -b .gniv4map
%patch7 -p1 -b .cleanups
%patch8 -p1 -b .time2038

# regenerate configure script etc.
./buildconf

%build
# disable setpshared and sem_open, which only work on NPTL kernels
# force detection of sys_siglist[] since 2.57's AC_DECL_SYS_SIGLIST
# is useless
cat > config.cache <<EOF
ac_cv_func_pthread_mutexattr_setpshared=no
ac_cv_func_sem_open=no
ac_cv_have_decl_sys_siglist=yes
EOF
%configure -C \
        --includedir=%{_includedir}/apr-%{aprver} \
        --with-installbuilddir=%{_libdir}/apr/build \
        --with-devrandom=/dev/urandom \
        CC=gcc CXX=g++
make %{?_smp_mflags} && make dox

%ifnarch x86_64
# https://bugzilla.redhat.com/bugzilla/show_bug.cgi?id=97611
%check
# Run non-interactive tests
pushd test
make %{?_smp_mflags} testall
TZ=PST8PDT ./testall -v || exit 1
popd
%endif

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
* Mon Jul 19 2004 Joe Orton <jorton@redhat.com> 0.9.4-2.1
- merge fixes for:
 * cleanup structure reuse
 * only do AF_INET reverse lookups of v4-mapped IPv6 addresses
 * apr_temp_dir_get() fixes (#128144)
 * apr_time_exp_get() handling dates in 2038 (Philip Martin)

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
