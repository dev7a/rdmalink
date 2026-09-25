# Security policy

## Reporting a vulnerability

Report privately, not in a public issue. Use GitHub's private vulnerability
reporting for this repository:
[**Report a vulnerability**](https://github.com/dev7a/rdmalink/security/advisories/new)
(Security → Advisories → Report a vulnerability). That opens a draft security
advisory only the maintainer and you can read.

Please include the app version (its `release.json` or the About window), the
macOS build, and the smallest sequence of steps that shows the problem. A
diagnostics file — Help → **Save Diagnostics File…** — is usually the fastest
way to describe the machine.

You should get a reply within a week. If a week passes with no answer, open a
public issue saying only that you are waiting on a security report, with no
details.

## What is in scope

RDMALink is a non-sandboxed macOS app that changes network configuration, so
the interesting surface is small and specific:

- **The authorized session.** The app asks macOS for
  `system.services.systemconfiguration.network`, holds that right for one burst
  of writes, and drops it. Anything that widens that right, holds it longer
  than a burst, or performs a write the user did not agree to is in scope.
- **The private bridge interface.** Bridge membership is edited through the
  undocumented `SCBridgeInterface*` symbols, resolved with `dlsym` before use
  and verified by reading the kernel back. Anything that makes the app act on a
  symbol it did not verify, or change a port the user did not pick, is in scope.
- **The undo notes** in `~/Library/Application Support/RDMALink`, and anything
  that could make a restore write a configuration that was never captured.
- **The diagnostics file**, if it can be made to contain something it should
  not.
- **Distribution.** Releases are signed with a Developer ID, notarized and
  stapled by Apple, and built by `.github/workflows/release.yml` from a GPG-
  signed `v*` tag whose key is listed in `script/release/trusted-signers.asc`.
  A way to get an unsigned, unnotarized or unintended build published under
  this repository's releases is in scope, as is anything that lets a release be
  cut without that signed tag.

Out of scope: the RDMA system switch itself and Apple's Thunderbolt Bridge, both
of which are macOS's and not this app's; and anything that requires an attacker
who is already running code as an administrator on the same Mac.

## Supported versions

The most recent release. There are no maintained older branches.
