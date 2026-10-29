# AMAP releases

Collective releases of the Agent Mailbox Access Protocol (AMAP) implementation.
Each release manifest pins the exact commits of the connectors, local router,
and Sandy deployment that make up one AMAP release.

## Install sandy and a release

With Docker running, one command installs [sandy](https://github.com/rappdw/sandy)
(if it is not already on `PATH`) and the latest AMAP release, then starts the
router:

```bash
curl -fsSL https://raw.githubusercontent.com/proofpoint/amap-release/main/install.sh | bash
```

The installer reads the release manifest from this repository and puts each
component checkout under `~/amap` at the release tag. It refuses a tag that
doesn't point at the manifest's commit, and a deployment whose `siblings.json`
pins different commits than the manifest. It then runs the deployment's
`amap-sandy.py install --apply`, builds the router image, and starts the
router. Start agents afterwards with `sandy --start` in each workspace.

It differs from amap-deploy-sandy's own one-command installer, which follows
that repository's `main` branch. This one installs exactly what a release
records and leaves the checkouts detached at the release tag. It's safe to run
again. A checkout with local changes stops the install, and an existing host's
fleet domain and Codex conversation mode are kept.

Codex conversations default to [unified mode](#codex-unified-conversations).
The installer checks out the Codex connector and passes
`install --codex-mode unified`, but only when doing so changes no existing
sandbox. The release must support it, the host must not have chosen a mode
already, sandy must accept the Codex `agent_wrapper`, and sandy must report no
sandbox launched with Codex. Otherwise the host keeps its current mode and the
installer says why.

Settings, passed as environment variables to `bash`:

| Variable | Effect |
| --- | --- |
| `AMAP_RELEASE` | The release to install, such as `amap-2026-10-28`. Defaults to the latest. |
| `AMAP_DIR` | Where the checkouts go. Defaults to `~/amap`. |
| `SANDY_HOME` | sandy's home. Defaults to `~/.sandy`. |
| `AMAP_CODEX=1` | Also check out amap-connector-codex, so Codex sandboxes get a delivery supervisor. |
| `AMAP_CODEX_MODE` | `unified` or `separate`: author the fleet's Codex conversation mode, overriding the default above. `unified` checks out the Codex connector. |
| `AMAP_FLEET_DOMAIN_BASE` | A fresh host's fleet domain is `sandy.<host>.<this>`. Defaults to `internal`. |

For example, to keep separate Codex conversations on a fresh host:

```bash
curl -fsSL https://raw.githubusercontent.com/proofpoint/amap-release/main/install.sh | AMAP_CODEX_MODE=separate bash
```

On a host that already runs Codex sandboxes, read
[Codex unified conversations](#codex-unified-conversations) before setting
`AMAP_CODEX_MODE=unified`.

## Releases

| Release | Manifest | Captured | Scope |
| --- | --- | --- | --- |
| `amap-2026-10-28` | [Manifest](releases/amap-2026-10-28/amap-2026-10-28.json) | October 28, 2026 | Codex unified conversations |
| `amap-2026-10-10` | [Manifest](releases/amap-2026-10-10/amap-2026-10-10.json) | October 16, 2026 | First collective release |

### Release candidates

A release candidate is labelled `amap-<name>-rcN`. It's a pre-release: the
installer never picks it by default, and it doesn't change the latest release.
Its manifest also records each pinned commit's `tree`, and the installer
verifies it.

| Candidate | Manifest | Status |
| --- | --- | --- |
| `amap-m1p1-rc1` | [Manifest](releases/amap-m1p1-rc1/amap-m1p1-rc1.json) | M1 phase 1 component set; not a validated release |

Install a candidate by naming it:

```bash
curl -fsSL https://raw.githubusercontent.com/proofpoint/amap-release/main/install.sh | AMAP_RELEASE=amap-m1p1-rc1 bash
```

`amap-m1p1-rc1` pins amap-router-local twice. The second pin, the hop
renderer's router, is checked out as `amap-router-local-hop` at its own tag,
`amap-m1p1-rc1-hop`.

The release date is a label. The manifest preserves the actual capture time,
component commit dates, full commit hashes, remote URLs, and annotated tag
object hashes. The component repositories carry matching `amap-YYYY-MM-DD`
release tags. This repository tags each release as plain `YYYY-MM-DD` and
publishes it as a [GitHub release](https://github.com/proofpoint/amap-release/releases),
so release `amap-2026-10-10` is tag `2026-10-10` here.

### amap-2026-10-28

Codex agents can now take human interaction and incoming AMAP work in one
persistent conversation. The release is based on `amap-2026-10-10` and changes
only the Codex connector and the Sandy deployment. The Claude connector and
router pins are unchanged.

| Repository | Commit | Change |
| --- | --- | --- |
| [amap-connector-claude](https://github.com/proofpoint/amap-connector-claude.git) | `3a20c28080ad560a55e202ea59596c1ae1733661` | Unchanged |
| [amap-connector-codex](https://github.com/proofpoint/amap-connector-codex) | `e10eb2cf22a1056d1506938ef0669bfde582ff75` | Updated |
| [amap-deploy-sandy](https://github.com/proofpoint/amap-deploy-sandy.git) | `3b605d028ad312442e9569b9a9e7fcfe7f4c9efb` | Updated |
| [amap-router-local](https://github.com/proofpoint/amap-router-local.git) | `972cb7096bf4110811cbafc20a6a8019d7408576` | Unchanged |

The deployment commit is on amap-deploy-sandy's `release/amap-2026-10-10`
line. It includes the installed readiness-checker fix
([amap-deploy-sandy#108](https://github.com/proofpoint/amap-deploy-sandy/pull/108))
and the `install.sh` umask fix
([amap-deploy-sandy#114](https://github.com/proofpoint/amap-deploy-sandy/pull/114)).
Its `siblings.json` pins the same three component commits as the manifest.

**Re-cut on October 28.** This release was first published with the
deployment at `e4e53626a80f5f2da18db91969091b6d65beb9c4` (tag object
`84e24100c5cd2033a6d136c02d5e721f0bc5421a`). Its `install.sh` failed silently
under a umask of `002` with the Codex connector checked out
([amap-deploy-sandy#113](https://github.com/proofpoint/amap-deploy-sandy/issues/113)).
The deployment pin moved to its child `3b605d0`, which changes only
`install.sh` and its tests. amap-deploy-sandy's `amap-2026-10-28` tag and this
repository's `2026-10-28` tag were re-pointed, and the backup was rebuilt. The
other three component tags are unchanged. A checkout fetched before the re-cut
keeps the old tags: run `git fetch --tags --force` to update them.

#### Codex unified conversations

**Activation is explicit.** Unified mode is one fleet-wide choice:

```bash
cd ~/amap/amap-deploy-sandy
AMAP_CODEX=1 python3 amap-siblings.py          # confirm the pins (dry run)
python3 amap-sandy.py install --codex-mode unified           # preview
python3 amap-sandy.py install --codex-mode unified --apply
```

The one-command installer passes this choice by default on a host with no Codex
sandboxes, and with `AMAP_CODEX_MODE=unified` on any host. The choice sets `feature.codex_conversation_mode = "unified"` in the manifest. A
later ordinary install keeps it. The host's sandy must support the protected
Codex `agent_wrapper`, or install refuses the choice. Unified mode applies only
to **newly created** Codex-served sandboxes launched with
`SANDY_SKIP_PERMISSIONS=true`. Mixed Claude/Codex sandboxes are Claude-served
and are refused by the unified wrapper.

**Separate mode stays available.** The deployment's `install` keeps separate
mode unless `--codex-mode unified` is passed, and `AMAP_CODEX_MODE=separate`
keeps it with the one-command installer. Separate mode keeps its native-config
and default model behavior. Installing or publishing this release doesn't
migrate, adopt, or erase any existing Codex state.

**Existing sandboxes need an operator procedure.** An existing Codex sandbox
with partial, ambiguous, or separate-mode state is held, not converted. To move
one to unified mode, the operator recreates it deliberately: inventory and
retain what's needed, resolve pending work and router custody, stop the agent
and router, prove quiescence, reset the slug through the router, remove the
sandbox, create the fresh one, restart the router, and establish fresh first
sight before sending work. Removal discards the sandbox's native history and
mailbox contents. Follow the release line's runbook exactly:

- [Fleet choice: fresh unified Codex conversations](https://github.com/proofpoint/amap-deploy-sandy/blob/3b605d028ad312442e9569b9a9e7fcfe7f4c9efb/docs/TUTORIAL.md#fleet-choice-fresh-unified-codex-conversations)
- [Recreating existing Codex-only sandboxes deliberately](https://github.com/proofpoint/amap-deploy-sandy/blob/3b605d028ad312442e9569b9a9e7fcfe7f4c9efb/docs/TUTORIAL.md#recreating-existing-codex-only-sandboxes-deliberately)

Adoption of an existing saved conversation, which keeps its history, is
[documented as experimental](https://github.com/proofpoint/amap-deploy-sandy/blob/3b605d028ad312442e9569b9a9e7fcfe7f4c9efb/docs/TUTORIAL.md#experimental-unified-conversation-existing-instance-transition)
and isn't supported in this release. On this release line, normal Sandy
startup holds an adopted sandbox instead of reopening its conversation. The
fix ([amap-deploy-sandy#109](https://github.com/proofpoint/amap-deploy-sandy/pull/109))
is on amap-deploy-sandy's `main` only.

Check a fresh unified sandbox before sending it work. Require `ready: true`,
`initialization_phase: "initialized"`, and a verified canonical ID:

```bash
sandy --exec --workspace "$WORKSPACE" -- python3 /opt/sandy/features/amap/codex/codex_fresh.py --state /opt/sandy/feature-state/amap/codex inspect
```

#### Validation

The manifest's `validation` and `evidence` fields hold the full record.

- **Pins agree.** amap-deploy-sandy's `siblings.json` at `3b605d0` names the
  same Claude connector, Codex connector, and router commits as the manifest.
- **CI.** Every required job passed for each pinned commit. `3b605d0` is the
  merge of [#114](https://github.com/proofpoint/amap-deploy-sandy/pull/114). Its
  tree is identical to the pull request head, where
  [CI ran](https://github.com/proofpoint/amap-deploy-sandy/actions/runs/40811084590)
  (Python 3.9, 3.13, and the sibling-main canary). Codex connector:
  [run](https://github.com/proofpoint/amap-connector-codex/actions/runs/40322736927).
  Claude connector: [run](https://github.com/proofpoint/amap-connector-claude/actions/runs/37571077697).
  Router: [run](https://github.com/proofpoint/amap-router-local/actions/runs/39136973647).
- **Local re-run** (October 28, Python 3.13, all four checkouts at their pins):
  amap-deploy-sandy 788 tests passed; amap-connector-codex 665 tests passed,
  and 44 spec fixtures checked with none unexpected.
- **Installed payload.** Real Codex 0.164.0 human and
  queued-before-startup/restart probes pass against an actually installed
  payload ([#108](https://github.com/proofpoint/amap-deploy-sandy/pull/108)).
  The re-cut changes only `install.sh` and its tests, not the payload.

Evidence for each required behavior, from real Codex 0.164.0 with disposable
homes and synthetic local inference:

| Behavior | Evidence |
| --- | --- |
| Fresh unified startup | [amap-deploy-sandy#106](https://github.com/proofpoint/amap-deploy-sandy/pull/106): four concurrent human/queued-message pairs, including work queued before first startup; [#108](https://github.com/proofpoint/amap-deploy-sandy/pull/108) on the installed payload |
| Canonical thread kept across restart | #106 same-canonical restart; Codex connector `compatibility/unified-runtime-0.164.0.json` (`restart_exact_history_without_replay`, `resume_last_maps_to_canonical`) |
| Incoming work queued during human activity | `unified-runtime-0.164.0.json` (`queue_waits_for_human`, `human_and_peer_same_pane`); `unified-protocol-0.164.0.json` (`native_human_busy_state_visible`) |
| Detached delivery | `unified-runtime-0.164.0.json` (`detached_mail_completes`, `reattached_final_response_visible`) |
| No replay after restart | #106; `unified-protocol-0.164.0.json` (`reattach_same_history_without_replay`); Codex connector tests `test_durable_acceptance_no_replay` and `test_finished_notice_is_never_replayed_after_scan_and_restart` |

This is synthetic native evidence. It uses no user credentials, external
inference, or fleet traffic, and doesn't establish acceptance on a target
host. Run the both-direction Claude/Codex pilot in the runbook before relying
on unified mode.

### amap-2026-10-10

| Repository | Commit |
| --- | --- |
| [amap-connector-claude](https://github.com/proofpoint/amap-connector-claude.git) | `3a20c28080ad560a55e202ea59596c1ae1733661` |
| [amap-connector-codex](https://github.com/proofpoint/amap-connector-codex) | `87347ad49837563678f50c4119248ecd2dda048d` |
| [amap-deploy-sandy](https://github.com/proofpoint/amap-deploy-sandy.git) | `ef93e4f179ebe13470e11e982fdf465f709f0530` |
| [amap-router-local](https://github.com/proofpoint/amap-router-local.git) | `972cb7096bf4110811cbafc20a6a8019d7408576` |

Errata, found on October 28 and left uncorrected in the manifest:

- amap-deploy-sandy's `siblings.json` at `ef93e4f` pins amap-connector-claude
  at `ca9b40647c5c002e6e6fe30b4fea54e64a76af57`, two commits before the
  manifest's `3a20c28`. The one-command installer therefore refuses this
  release.
- amap-router-local's published `amap-2026-10-10` tag was re-created on
  October 18 as tag object `cf97d35b1f58d86e267fb2537e28c2f510b01384`. It
  points at the manifest's commit, but its tag object differs from the one the
  manifest records.

## Check out a release

For a fresh checkout without installing, run the following commands in a new
workspace, with `RELEASE` set to a release label. These commands contact
GitHub and create four new directories.

```bash
RELEASE=amap-2026-10-28
git clone --branch "$RELEASE" https://github.com/proofpoint/amap-connector-claude.git amap-connector-claude
git clone --branch "$RELEASE" https://github.com/proofpoint/amap-connector-codex amap-connector-codex
git clone --branch "$RELEASE" https://github.com/proofpoint/amap-deploy-sandy.git amap-deploy-sandy
git clone --branch "$RELEASE" https://github.com/proofpoint/amap-router-local.git amap-router-local
```

Each checkout is detached at the release tag. Compare `git rev-parse HEAD`
against the manifest's `commit` value before using it. Component READMEs contain
installation and configuration instructions.

## Restore the offline backup

Each release's self-contained backup archive contains four Git bundles, the
original manifest, checksums, and `RESTORE.txt`. Each archive was verified by
restoring all four repositories and checking their release commits, tag
objects, and Git object integrity.

The archive is stored separately from this repository (backup to your own
storage). This repository tracks its SHA-256 checksum beside the manifest.
After obtaining the archive, place it and the checksum file in one directory:

```bash
RELEASE=amap-2026-10-28
sha256sum -c "$RELEASE-backup.tar.gz.sha256"
tar -xzf "$RELEASE-backup.tar.gz"
cd "$RELEASE"
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
   Confirm the deployment's `siblings.json` pins the same commits.
4. Create and verify an offline backup, store it separately, and add its
   checksum alongside the manifest.
5. Add the release to this README, set `LATEST_RELEASE` in `install.sh`, and
   commit the release record. Publish the component tags and this repository
   when ready to share them.
6. Tag the release record in this repository as `YYYY-MM-DD` (without the
   `amap-` prefix), push the tag, and create a matching GitHub release.

Keep existing release records intact. Use a new release label for a different
combination of component commits.

## License

Copyright 2026 Proofpoint, Inc.

Licensed under the [Apache License, Version 2.0](LICENSE), matching the component
repositories.
