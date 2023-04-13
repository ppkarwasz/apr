# APR/APU release process

## 1) Release basics
1. set APR_DEV_TOOLS to the parent directory of this readme, e.g. APR_DEV_TOOLS=$HOME/SRC/apr-site/tools
2. set your working directory to a clean checkout of the project you're releasing
3. Tag an rc:

   ```
    $APR_DEV_TOOLS/r0-make-candidate.sh rc1
   ```
4. cd $APR_DEV_TOOLS and read/run release.sh pointing to the tag created
   by r0-make-candidate.sh.
5. Add the generated tarballs, sigs, checksums, etc to checkout of https://dist.apache.org/repos/dist/dev/apr
   - XXX: Need to borrow automation from httpd-dev-tools/release
6. Announce the vote w/ the links to dist/dev/apr
7. Wait for results and repeat or release
8. If unsuccessful, cleanup https://dist.apache.org/repos/dist/dev/apr and repeat with a later rcX.
9. On successful release
   1. rename the tag to drop the -rcX-candidate suffix
   2. rename the files to drop the -rxX suffix
   3. svn mv them from dist/dev/ to dist/release
      - wait for dlcdn links (immediate) and directory listings (up to 2 hours) to show the new files.
      - update the Announcement txt and html on dist/dev and copy it.
      - update the download and index xdocs/ as in r1840948
   4. Update CHANGES-* on dist/release/apr
      e.g. https://www.apache.org/dist/apr/CHANGES-APR-1.7
   5. Send announce emails to apr and announce@ (see r6-announce.sh in this dir)

## 2) If there were CVES

1. set CVEs to READY on the cveprocess site
   - Use the 'OSS/ASF Emails' tab for the emails you should send to oss-security
     and to Apache lists.
   - Fill in a 'reference' tag 'vendor-advisory' with the URL to your public post about
     this issue (the same emails ent in the preceding sub-bullet(
   - ASF Security will be notified and will submit to the CVE
     project and then set state to 'PUBLIC'.
2. Add any CVE details if applicable to the CHANGES and commit and copy to dist/apr

## 3) Cleanup

1. Clean up prior release artifacts on dist
2. Add a new CHANGES banner
3. Add releases to reporter.apache.org and bz.apache.org
       https://reporter.apache.org/addrelease.html?apr
       https://bz.apache.org/bugzilla/editproducts.cgi?action=edit&product=APR
