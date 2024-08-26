# APR/APU release process

## 0) prep

1. Remind yourself of your GPG password
2. Make sure your key is in the KEYS file of the project and has some useful signatures.

## 1) Release basics

1. set APR_DEV_TOOLS to the parent directory of this readme, e.g. APR_DEV_TOOLS=$HOME/SRC/apr-site/release
2. set your working directory to a clean checkout of the project you're releasing (`svn cleanup . --remove-unversioned`)
3. Tag an rc (the version is taken from include/apX_version.h)

   ```
    $APR_DEV_TOOLS/r0-make-candidate.sh rc1
   ```
4. From the same project directory, run `$APR_DEV_TOOLS/release.sh` pointing to the tag created
   by r0-make-candidate.sh.

   The PROJECT and TAG parms are printed after the text "creating release candidate:" of the preceding step.

5. Review the generated tarballs in the dist/ subdirectory. If they look reasonable, run the following
   to add the generated tarballs, sigs, checksums, etc to checkout of https://dist.apache.org/repos/dist/dev/apr

   ```
   $APR_DEV_TOOLS/r2-prep-vote.sh
   ```
6. Announce the vote w/ the output produced from the above
7. Wait for results and repeat or release
8. If unsuccessful, cleanup https://dist.apache.org/repos/dist/dev/apr and repeat with a later rcX.
9. On successful vote:
   1. Run `$APR_DEV_TOOLS/r3-push-release-tars.sh` from your APR checkout to fixup and move the artifacts from dev/ to release
   2. Run `$APR_DEV_TOOLS/r4-stage-release.sh` to stage an update to the project checkout and website.  Review the changes.
   3. Wait for dlcdn links (immediate) and directory listings (up to 2 hours) to show the new files.
      - https://dist.apache.org/repos/dist/release/apr/
      - https://dlcdn.apache.org/apr/
   4. Run `$APR_DEV_TOOLS/r5-commit-staged-release.sh` to update the website and dev tree (and remove n-1 release)
   5. Run r6-announce.sh from this dir to generate announce emails (output will tell you what to do)

## 2) If there were CVES

0. Wait for either the dev@apr or announce@a.o emails to be visible.
1. Process the CVEs on the cveprocess site
   - Set the CVE to `READY`
   - Find the revision[s] used to backport the security fix and:
     - amend the commit messages to mention the CVE number (you can append the entire CHANGES entry)
       `svn propedit --revprop -r... svn:log`
     - add a timeline entry to the CVE 
       > fixed by rXXX in 1.7.x
   - Use the 'OSS/ASF Emails' tab to send the emails to oss-security and to Apache lists.
   - Find the CVE email to dev@apr on lists.apache.org and grab a permalink
   - Fill in a 'reference' tag 'vendor-advisory' with the URL to your public post about
     this issue (the permalink to dev@apr ANNOUNCEMENT)a
   - Save the CVE entry.
   - ASF Security will be notified and will submit to the CVE project and then set state to 'PUBLIC'.
2. Add any CVE details if applicable to the CHANGES and commit and copy to dist/apr
3. Edit the CVE info into the revisions that fixed them in the backport, e.g. 
4. Add the release to bugzilla: https://bz.apache.org/bugzilla/editversions.cgi?action=add&product=apr

## 3) Cleanup

1. Add releases to reporter.apache.org and bz.apache.org
       https://reporter.apache.org/addrelease.html?apr
       https://bz.apache.org/bugzilla/editproducts.cgi?action=edit&product=APR
2. Update doap.rdf in apr-site
