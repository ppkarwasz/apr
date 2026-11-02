# APR/APU release process

## 0) prep

1. Remind yourself of your GPG password
2. Make sure your key is in the KEYS file of the project and has some useful signatures.
3. Check CVE status in https://svn.apache.org/repos/private/pmc/apr checkout and make sure the ready items
   are what you expect.

## 1) Release basics

1. set APR_DEV_TOOLS to the parent directory of this readme, e.g. APR_DEV_TOOLS=$HOME/SRC/apr-site/release
2. set your working directory to a clean checkout of the project you're releasing (`svn cleanup . --remove-unversioned`)
3. Tag an rc (the version is taken from include/apX_version.h)

   ```
    $APR_DEV_TOOLS/r0-make-candidate.sh rc1
   ```
4. From the same project directory, build the candidate tarballs, checksums and signatures:

   ```
    $APR_DEV_TOOLS/r1-release.sh -u covener@apache.org
   ```

   For apr-util, also pass `-a /path/to/apr-source` (or set `$APR_SOURCE`) so buildconf finds APR,
   e.g. `$APR_DEV_TOOLS/r1-release.sh -u covener -a $HOME/SRC/apr-1.7.x/`.

   This is a thin wrapper that calls `release.sh` with the PROJECT and TAG recorded by the previous
   step in `dist/VERSION`. `release.sh PROJECT TAG [SIGNING-USER] [APR-SOURCE]` can still be run by
   hand; the PROJECT and TAG parms are printed after the text "creating release candidate:" of the
   preceding step.

5. Review the generated tarballs in the dist/ subdirectory. A quick way to do that is to diff the
   candidate against the latest release of the same project in https://dist.apache.org/repos/dist/release/apr/:

   ```
   $APR_DEV_TOOLS/r1b-compare-release.sh -q
   ```

   This downloads and sha256-verifies the latest `m.n.x` release tarball, unpacks both under `dist/compare/`
   and prints a recursive diff. Generated autotools files are excluded by default (`-g` includes them),
   `-q` lists only changed files, `-r REL` picks a specific release. Nothing is uploaded or committed.

   If they look reasonable, run the following
   to add the generated tarballs, sigs, checksums, etc to checkout of https://dist.apache.org/repos/dist/dev/apr

   ```
   $APR_DEV_TOOLS/r2-prep-vote.sh
   ```
6. Announce the vote w/ the output produced from the above
7. Wait for results and repeat or release
8. If unsuccessful, cleanup https://dist.apache.org/repos/dist/dev/apr and repeat with a later rcX.
9. On successful vote:
   1. Run `$APR_DEV_TOOLS/r3-push-release-tars.sh` from your APR checkout to fixup and move the artifacts from dev/ to release
   2. Run `$APR_DEV_TOOLS/r4-stage-release.sh` to stage an update to the project checkout and website.  

      Review the changes, especially ./CHANGES and dist/apache.org-dist/release/apr/CHANGES-*

      If something goes wrong and you need to re-run, `svn revert CHANGES NOTICE STATUS include/apu_version.h`

   3. Wait for dlcdn links to work. Directory listings will lag, but you can
      test the direct links until they appear.  dist.apache.org should work immediately.
      - https://dist.apache.org/repos/dist/release/apr/
      - https://dlcdn.apache.org/apr/
   4. Run `$APR_DEV_TOOLS/r5-commit-staged-release.sh` to update the website and dev tree (and remove n-1 release)
   5. Run `$APR_DEV_TOOLS/r6-announce.sh` to generate announce emails (output will tell you what to do)

## 2) If there were CVES

1. Wait for either the dev@apr or announce@a.o emails to be visible.
1. Update CVE's with backport info

   Mostly automated, See apr-site/tools/update_svn_logs_with_cve.py.

   If done manually:

   1. vendor-advisory reference of https://apr.apache.org/security_report.html
   2. timeline entry of "fixed in 1.6.x by rXXXXX" for latest release stream.
   3. Synch website and CVE.json in SECURITY repo

1. Process the CVEs on the cveprocess site
   - Set the CVE to `READY`
   - Use $APR_SECURITY/tools/update_svn_logs_with_cve.py to add the CVE to the stable releases svn commit messages.
   - add a timeline entry to the CVEs:
     ```
     $APR_SECURITY/tools/update_svn_logs_with_cve.py ~/data/apu164 --cveprocess /tmp/cve.sh
     ```
     And run the resulting /tmp/cve.sh from $APR_SECURITY/ answering the many prompts (watch the diff closely!)

   - Use the 'OSS/ASF Emails' tab to save then send the emails to oss-security and to Apache lists.
   - Find the CVE email to dev@apr on lists.apache.org and grab a permalink
   - Fill in a 'reference' tag 'vendor-advisory' with the URL to your public post about
     this issue (the permalink to dev@apr ANNOUNCEMENT)a
   - Save the CVE entry.
   - ASF Security will be notified and will submit to the CVE project and then set state to 'PUBLIC'.

## 3) Cleanup

1. Add releases to reporter.apache.org and bz.apache.org
       https://reporter.apache.org/addrelease.html?apr
       https://bz.apache.org/bugzilla/editproducts.cgi?action=edit&product=APR
2. Update doap.rdf in apr-site (https://svn.apache.org/repos/asf/apr/site/trunk)
3. In https://svn.apache.org/repos/private/pmc/apr, move resolved CVE's 
   from SECURITY/CVE-XXXX to security-reports/resolved/
4. svn rm the $project-$version dir under SECURITY/ too (not done by any release script)
5. Copy CVE.json's to security-json/



## TODOS

- Add timeline entry, either like httpd or while adding the backports revisions
- automate copying CVE's to security-json in apr-site

  Requires timeline entry.
