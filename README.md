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

Settings, passed as environment variables to `bash`:

| Variable | Effect |
| --- | --- |
| `AMAP_RELEASE` | The release to install, such as `amap-2026-10-28`. Defaults to the latest. |
| `AMAP_DIR` | Where the checkouts go. Defaults to `~/amap`. |
| `SANDY_HOME` | sandy's home. Defaults to `~/.sandy`. |
| `AMAP_CODEX=1` | Also check out amap-connector-codex, so Codex sandboxes get a delivery supervisor. |
| `AMAP_CODEX_MODE` | `unified` or `separate`: author the fleet's Codex conversation mode. Implies `AMAP_CODEX=1`. Unset keeps the host's current mode. |
| `AMAP_FLEET_DOMAIN_BASE` | A fresh host's fleet domain is `sandy.<host>.<this>`. Defaults to `internal`. |

For example, to install with unified Codex conversations for newly created
Codex sandboxes:

```bash
curl -fsSL https://raw.githubusercontent.com/proofpoint/amap-release/main/install.sh | AMAP_CODEX_MODE=unified bash
```

Read [Codex unified conversations](#codex-unified-conversations) first if the
host already runs Codex sandboxes.

## Releases

| Release | Manifest | Captured | Scope |
| --- | --- | --- | --- |
| `amap-2026-10-28` | [Manifest](releases/amap-2026-10-28/amap-2026-10-28.json) | October 28, 2026 | Codex unified conversations |
| `amap-2026-10-10` | [Manifest](releases/amap-2026-10-10/amap-2026-10-10.json) | October 16, 2026 | First collective release |

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
| [amap-deploy-sandy](https://github.com/proofpoint/amap-deploy-sandy.git) | `e4e53626a80f5f2da18db91969091b6d65beb9c4` | Updated |
| [amap-router-local](https://github.com/proofpoint/amap-router-local.git) | `972cb7096bf4110811cbafc20a6a8019d7408576` | Unchanged |

The deployment commit is on amap-deploy-sandy's `release/amap-2026-10-10`
line. It includes the installed readiness-checker fix
([amap-deploy-sandy#108](https://github.com/proofpoint/amap-deploy-sandy/pull/108)),
and its `siblings.json` pins the same three component commits as the manifest.

#### Codex unified conversations

**Activation is explicit.** Unified mode is one fleet-wide choice:

```bash
cd ~/amap/amap-deploy-sandy
AMAP_CODEX=1 python3 amap-siblings.py          # confirm the pins (dry run)
python3 amap-sandy.py install --codex-mode unified           # preview
python3 amap-sandy.py install --codex-mode unified --apply
```

The one-command installer does the same with `AMAP_CODEX_MODE=unified`. The
choice sets `feature.codex_conversation_mode = "unified"` in the manifest. A
later ordinary install keeps it. The host's sandy must support the protected
Codex `agent_wrapper`, or install refuses the choice. Unified mode applies only
to **newly created** Codex-served sandboxes launched with
`SANDY_SKIP_PERMISSIONS=true`. Mixed Claude/Codex sandboxes are Claude-served
and are refused by the unified wrapper.

**Separate mode stays the default.** A host that doesn't choose unified mode
keeps separate mode, with its native-config and default model behavior.
Installing or publishing this release doesn't migrate, adopt, or erase any
existing Codex state.

**Existing sandboxes need an operator procedure.** An existing Codex sandbox
with partial, ambiguous, or separate-mode state is held, not converted. To move
one to unified mode, the operator recreates it deliberately: inventory and
retain what's needed, resolve pending work and router custody, stop the agent
and router, prove quiescence, reset the slug through the router, remove the
sandbox, create the fresh one, restart the router, and establish fresh first
sight before sending work. Removal discards the sandbox's native history and
mailbox contents. Follow the release line's runbook exactly:

- [Fleet choice: fresh unified Codex conversations](https://github.com/proofpoint/amap-deploy-sandy/blob/e4e53626a80f5f2da18db91969091b6d65beb9c4/docs/TUTORIAL.md#fleet-choice-fresh-unified-codex-conversations)
- [Recreating existing Codex-only sandboxes deliberately](https://github.com/proofpoint/amap-deploy-sandy/blob/e4e53626a80f5f2da18db91969091b6d65beb9c4/docs/TUTORIAL.md#recreating-existing-codex-only-sandboxes-deliberately)

Adoption of an existing saved conversation, which keeps its history, is
[documented as experimental](https://github.com/proofpoint/amap-deploy-sandy/blob/e4e53626a80f5f2da18db91969091b6d65beb9c4/docs/TUTORIAL.md#experimental-unified-conversation-existing-instance-transition)
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

- **Pins agree.** amap-deploy-sandy's `siblings.json` at `e4e5362` names the
  same Claude connector, Codex connector, and router commits as the manifest.
- **CI.** Every required job passed for each pinned commit. `e4e5362` is the
  merge of [#108](https://github.com/proofpoint/amap-deploy-sandy/pull/108). Its
  tree is identical to the pull request head, where
  [CI ran](https://github.com/proofpoint/amap-deploy-sandy/actions/runs/40375092343)
  (Python 3.9, 3.13, and the sibling-main canary). Codex connector:
  [run](https://github.com/proofpoint/amap-connector-codex/actions/runs/40322736927).
  Claude connector: [run](https://github.com/proofpoint/amap-connector-claude/actions/runs/37571077697).
  Router: [run](https://github.com/proofpoint/amap-router-local/actions/runs/39136973647).
- **Local re-run** (October 28, Python 3.13, all four checkouts at their pins):
  amap-deploy-sandy 785 tests passed; amap-connector-codex 665 tests passed,
  and 44 spec fixtures checked with none unexpected.
- **Installed payload.** Real Codex 0.164.0 human and
  queued-before-startup/restart probes pass against an actually installed
  payload ([#108](https://github.com/proofpoint/amap-deploy-sandy/pull/108)).

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
