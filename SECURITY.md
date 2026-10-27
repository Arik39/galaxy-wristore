# Security policy

Galaxy Wristore connects to watches on your network, installs packages on them and reads backup files, so security
problems matter. Thank you for reporting them responsibly.

## Report a vulnerability

Please do not open a public issue. Report it privately instead: on the repository's
[Security tab](https://github.com/Arik39/galaxy-wristore/security), choose **Report a vulnerability**.

Include what an attacker could do, the steps to reproduce it, and the app version, phone and watch you used. Once a
fix is released, you are credited in the release notes unless you would rather not be.

## Supported versions

Fixes go into the latest release. Please check that the problem is still there in it before you report.

## In scope

- The connection to the watch (`sdb`) and the key the app uses to authorise it.
- Downloading and checking packages from Tizen Archive.
- Reading `.tpk`, `.wgt` and `.twbackup` files, which may come from anyone.
- Anything that sends data off the phone other than to Tizen Archive or your watch.

Problems in the watch's own software, or in Tizen Archive's service, belong to their owners.
