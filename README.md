# RDMALink

A macOS utility that prepares Thunderbolt 5 ports for RDMA over Thunderbolt on
the Mac it runs on: it takes a port out of the Thunderbolt Bridge, gives it its
own IPv6 link-local service, keeps an undo note, and can put everything back.
Run it on each Mac of a pair or cluster and pick the ports.

Requires macOS 27 on a Mac with Thunderbolt 5. Not sandboxed; distributed as a
notarized download, never through the App Store.

- Design: [docs/UX_SPEC.md](docs/UX_SPEC.md)
- Architecture and decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Build and test: `script/test.sh`
