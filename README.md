# AMAP releases

Collective releases of the Agent Mailbox Access Protocol (AMAP) implementation.
Each release manifest pins the exact commits of the connectors, local router,
and Sandy deployment that make up one AMAP release.

## Releases

| Release | Manifest | Captured |
| --- | --- | --- |
| `amap-2026-10-10` | [Manifest](releases/amap-2026-10-10/amap-2026-10-10.json) | October 16, 2026 |

The release date is a label. The manifest preserves the actual capture time,
component commit dates, full commit hashes, remote URLs, and annotated tag
object hashes. The component repositories carry matching `amap-YYYY-MM-DD`
release tags. This repository tags each release as plain `YYYY-MM-DD` and
publishes it as a [GitHub release](https://github.com/proofpoint/amap-release/releases),
so release `amap-2026-10-10` is tag `2026-10-10` here.

### amap-2026-10-10

| Repository | Commit |
| --- | --- |
| [amap-connector-claude](https://github.com/proofpoint/amap-connector-claude.git) | `3a20c28080ad560a55e202ea59596c1ae1733661` |
| [amap-connector-codex](https://github.com/proofpoint/amap-connector-codex) | `87347ad49837563678f50c4119248ecd2dda048d` |
| [amap-deploy-sandy](https://github.com/proofpoint/amap-deploy-sandy.git) | `ef93e4f179ebe13470e11e982fdf465f709f0530` |
| [amap-router-local](https://github.com/proofpoint/amap-router-local.git) | `972cb7096bf4110811cbafc20a6a8019d7408576` |

## Check out a release

For a fresh checkout, run the following commands in a new workspace. These
commands contact GitHub and create four new directories.

```bash
git clone --branch amap-2026-10-10 https://github.com/proofpoint/amap-connector-claude.git amap-connector-claude
git clone --branch amap-2026-10-10 https://github.com/proofpoint/amap-connector-codex amap-connector-codex
git clone --branch amap-2026-10-10 https://github.com/proofpoint/amap-deploy-sandy.git amap-deploy-sandy
git clone --branch amap-2026-10-10 https://github.com/proofpoint/amap-router-local.git amap-router-local
```

Each checkout is detached at the release tag. Compare `git rev-parse HEAD`
against the manifest's `commit` value before using it. Component READMEs contain
installation and configuration instructions.

## Restore the offline backup

The self-contained backup archive contains four Git bundles, the original
manifest, checksums, and `RESTORE.txt`. The archive was verified by restoring
all four repositories and checking their release commits, tag objects, and
Git object integrity.

The archive is stored separately from this repository (backup to your own storage). 
This repository tracks its SHA-256 checksum. After obtaining the archive, place it and 
the checksum file in one directory:

```bash
sha256sum -c amap-2026-10-10-backup.tar.gz.sha256
tar -xzf amap-2026-10-10-backup.tar.gz
cd amap-2026-10-10
sha256sum -c SHA256SUMS
```

Follow `RESTORE.txt` to clone the included bundles without network access.
The backup preserves the tagged source and its reachable history. It excludes
ignored files, runtime data, installed dependencies, and configuration outside
Git.

## Record another release

1. Select the exact component commits and ensure the work to include is committed.
2. Choose a new `amap-YYYY-MM-DD` release label and create matching annotated
   tags in the component repositories.
3. Add `releases/<release>/<release>.json` with the component commit and tag
   hashes, remote URLs, and capture timestamp, following the existing manifest.
4. Create and verify an offline backup, store it separately, and add its
   checksum alongside the manifest.
5. Add the release to this README and commit the release record. Publish the
   component tags and this repository when ready to share them.
6. Tag the release record in this repository as `YYYY-MM-DD` (without the
   `amap-` prefix), push the tag, and create a matching GitHub release.

Keep existing release records intact. Use a new release label for a different
combination of component commits.

## License

Copyright 2026 Proofpoint, Inc.

Licensed under the [Apache License, Version 2.0](LICENSE), matching the component
repositories.
