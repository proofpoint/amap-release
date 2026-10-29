#!/usr/bin/env bash
# install.sh — sandy and one AMAP release on this host, in one command:
#
#   curl -fsSL https://raw.githubusercontent.com/proofpoint/amap-release/main/install.sh | bash
#
# It installs sandy if it is not on PATH (sandy's own installer, latest
# release), reads the release manifest from this repository, and puts each
# component checkout under $AMAP_DIR at the release tag, refusing a tag whose
# commit differs from the manifest. It then confirms the deployment's
# siblings.json pins the same commits, runs `amap-sandy.py install --apply`
# from the release's deployment checkout, builds the router image and starts
# the router. Agents are started afterwards, whenever and in any order, with
# `sandy --start`.
#
# Codex conversations default to unified mode: newly created Codex-served
# sandboxes use one persistent conversation for the pane and incoming work.
# The default is applied only where it changes no existing sandbox: the
# release supports it, the host has not chosen a mode, sandy accepts the
# Codex agent_wrapper, and sandy reports no sandbox launched with codex.
# Otherwise the host's current mode is kept and the installer says why.
#
# Unlike amap-deploy-sandy's install.sh, which follows that repository's main
# branch, this installs exactly the commits a release records. The checkouts
# are left detached at the release tag.
#
# Safe to run again: a checkout already at the release is left as it is,
# install is idempotent, a running router container is left running, and a
# stopped one is started. A checkout with local changes holds the install.
# An existing host's fleet domain and Codex conversation mode are kept unless
# asked for, and nothing migrates or erases existing Codex state.
#
# It needs no root and no credentials, and installs nothing outside $AMAP_DIR,
# $SANDY_HOME/features/amap (plus the router's state directory) and, when sandy
# is missing, sandy itself (~/.local/bin by default).
#
#   AMAP_RELEASE    the release to install    (default: the latest, below)
#   AMAP_DIR        where the checkouts go    (default: ~/amap)
#   SANDY_HOME      sandy's home              (default: ~/.sandy)
#   AMAP_CODEX=1    also check out amap-connector-codex, so Codex sandboxes
#                   get a delivery supervisor (implied by unified mode)
#   AMAP_CODEX_MODE=unified|separate
#                   author the fleet's Codex conversation mode, overriding the
#                   default above. Unified applies to newly created Codex-served
#                   sandboxes only; existing ones hold for the operator
#   AMAP_FLEET_DOMAIN_BASE  a fresh host's fleet domain is sandy.<host>.<this>
#                   (default: internal, non-routable)
#   AMAP_RELEASE_RAW  where release manifests are read from
#                   (default: this repository's main branch on GitHub)
set -euo pipefail

LATEST_RELEASE=amap-2026-10-28

AMAP_RELEASE="${AMAP_RELEASE:-$LATEST_RELEASE}"
AMAP_DIR="${AMAP_DIR:-$HOME/amap}"
SANDY_HOME="${SANDY_HOME:-$HOME/.sandy}"
AMAP_RELEASE_RAW="${AMAP_RELEASE_RAW:-https://raw.githubusercontent.com/proofpoint/amap-release/main}"
SANDY_INSTALLER=https://raw.githubusercontent.com/rappdw/sandy/main/install.sh
ROUTER_CONTAINER=amap-router-local
CODEX_REPO=amap-connector-codex

say() { printf '[amap] %s\n' "$*"; }
die() { printf '[amap] error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not on PATH. $2"; }

# checkout NAME URL COMMIT TAG TAG_OBJECT: $AMAP_DIR/NAME, detached at TAG,
# whose commit must be COMMIT.
checkout() {
  local name=$1 url=$2 commit=$3 tag=$4 tag_object=$5
  local dest="$AMAP_DIR/$name" cloned=0
  if [ -d "$dest/.git" ]; then
    [ -z "$(git -C "$dest" status --porcelain --untracked-files=no)" ] \
      || die "$dest has local changes. Commit or stash them, then re-run."
  elif [ -e "$dest" ]; then
    die "$dest exists and is not a git checkout. Move it aside, then re-run."
  else
    say "cloning $name into $dest"
    git clone --quiet --no-checkout "$url" "$dest"
    cloned=1
  fi
  # A local tag of the same name that differs is refused here, not replaced.
  git -C "$dest" fetch --quiet origin "refs/tags/$tag:refs/tags/$tag" \
    || die "$name: tag $tag could not be fetched, or a different local $tag exists."
  # The commit is the pin. A re-created tag on the same commit is reported.
  [ "$(git -C "$dest" rev-parse "refs/tags/$tag^{commit}")" = "$commit" ] \
    || die "$name: tag $tag does not point at the manifest's commit ($commit)."
  [ "$(git -C "$dest" rev-parse "refs/tags/$tag")" = "$tag_object" ] \
    || say "note: $name's tag $tag is not the tag object the manifest records (${tag_object:0:12}); its commit matches."
  # A fresh --no-checkout clone has no working tree, whatever its HEAD.
  if [ "$cloned" = 1 ] || [ "$(git -C "$dest" rev-parse -q --verify HEAD || true)" != "$commit" ]; then
    say "checking out $name at $tag (${commit:0:12})"
    git -C "$dest" -c advice.detachedHead=false checkout --quiet --detach "$commit"
  fi
  # install refuses a group- or world-writable protected Codex asset, which a
  # checkout made under a umask of 002 (Ubuntu's default) has.
  local writable
  writable=$(find "$dest" -path "$dest/.git" -prune -o -type f \( -perm -020 -o -perm -002 \) -print | wc -l)
  if [ "$writable" -gt 0 ]; then
    say "removing group/world write from $writable file(s) in $name"
    find "$dest" -path "$dest/.git" -prune -o -type f \( -perm -020 -o -perm -002 \) -exec chmod go-w {} +
  fi
}

# default_codex_mode MANIFEST: prints "unified" when the default may be
# applied, or nothing; why not goes to stderr.
default_codex_mode() {
  if [ -f "$1" ] && python3 -I -c '
import json, sys
sys.exit(0 if "codex_conversation_mode" in json.load(open(sys.argv[1])).get("feature", {}) else 1)
' "$1" 2>/dev/null; then
    say "this host already chose its Codex conversation mode; it was kept." >&2
    return 0
  fi
  if ! sandy --print-schema 2>/dev/null | python3 -I -c '
import json, sys
keys = json.load(sys.stdin).get("manifest", {}).get("top_level_keys", [])
sys.exit(0 if "agent_wrapper" in keys else 1)
'; then
    say "note: this sandy does not accept the Codex agent_wrapper, so Codex stays in separate mode." >&2
    return 0
  fi
  local codex
  codex=$(sandy --print-state 2>/dev/null | python3 -I -c '
import json, sys
names = [s.get("name", "?") for s in json.load(sys.stdin).get("sandboxes", [])
         if "codex" in (s.get("agents") or [])]
print(" ".join(names))
') || { say "note: sandy --print-state could not be read, so Codex stays in its current mode." >&2; return 0; }
  if [ -n "$codex" ]; then
    say "note: Codex sandboxes already exist ($codex), so Codex stays in its current mode." >&2
    say "  Unified mode would hold them until recreated. To choose it anyway, read the" >&2
    say "  release README's operator procedure, then re-run with AMAP_CODEX_MODE=unified." >&2
    return 0
  fi
  echo unified
}

main() {
  # The checkouts are the ones under $AMAP_DIR: an override pointing elsewhere
  # would install and build from a tree this script did not put at the release.
  unset AMAP_ROUTER_REPO AMAP_CONNECTOR_REPO AMAP_CODEX_CONNECTOR_REPO
  # Checkouts and installed files are the operator's alone.
  umask 022
  case "${AMAP_CODEX_MODE:-}" in
    ""|unified|separate) ;;
    *) die "AMAP_CODEX_MODE must be unified or separate (got: $AMAP_CODEX_MODE)." ;;
  esac
  case "$AMAP_RELEASE" in
    amap-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "AMAP_RELEASE must be a release label such as $LATEST_RELEASE (got: $AMAP_RELEASE)." ;;
  esac

  # --- what this host needs, checked before anything is written ------------
  need curl "Install curl, then re-run."
  need git "Install git, then re-run."
  need python3 "Install Python 3.9 or later, then re-run."
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' \
    || die "Python 3.9 or later is required; python3 is $(python3 -V 2>&1)."
  need docker "Install Docker (Docker Desktop, Rancher Desktop, Colima or Lima), then re-run."
  docker info >/dev/null 2>&1 || die "docker is installed but not answering. Start it, then re-run."

  # --- sandy -----------------------------------------------------------------
  if command -v sandy >/dev/null 2>&1; then
    say "sandy is installed ($(command -v sandy)); it was left as it is."
  else
    say "installing sandy (its latest release)"
    curl -fsSL "$SANDY_INSTALLER" | bash || die "the sandy installer failed; see above."
    export PATH="${INSTALL_DIR:-$HOME/.local/bin}:$PATH"
    command -v sandy >/dev/null 2>&1 || die "sandy was installed but is not on PATH; see above."
  fi

  # --- the release manifest ----------------------------------------------------
  local manifest
  manifest=$(curl -fsSL "$AMAP_RELEASE_RAW/releases/$AMAP_RELEASE/$AMAP_RELEASE.json") \
    || die "release $AMAP_RELEASE has no manifest at $AMAP_RELEASE_RAW. Check AMAP_RELEASE."
  # One line per repository: name, remote URL, commit, tag, tag object.
  local rows
  rows=$(printf '%s' "$manifest" | python3 -I -c '
import json, re, sys
m = json.load(sys.stdin)
for r in m["repositories"]:
    for k in ("commit", "tag_object"):
        if not re.fullmatch("[0-9a-f]{40}", r[k]):
            sys.exit("manifest field %s of %s is not a full commit hash" % (k, r["name"]))
    if not re.fullmatch(r"[A-Za-z0-9._-]+", r["name"]):
        sys.exit("manifest names an unexpected repository: %r" % r["name"])
    print(r["name"], r["remote_url"], r["commit"], r["tag"], r["tag_object"])
') || die "the manifest for $AMAP_RELEASE could not be read."

  # --- the checkouts, side by side, at the release tag -------------------------
  # The Codex connector is checked out once the conversation mode is known.
  mkdir -p "$AMAP_DIR"
  local name url commit tag tag_object codex_row=""
  while read -r -u 3 name url commit tag tag_object; do
    if [ "$name" = "$CODEX_REPO" ]; then
      codex_row="$name $url $commit $tag $tag_object"
    else
      checkout "$name" "$url" "$commit" "$tag" "$tag_object"
    fi
  done 3<<<"$rows"

  # The deployment's own pins must name the same commits as the manifest.
  local deploy="$AMAP_DIR/amap-deploy-sandy"
  printf '%s' "$rows" | python3 -I -c '
import json, sys
manifest = {n: c for n, _, c, _, _ in (l.split() for l in sys.stdin.read().splitlines())}
pins = {s["name"]: s["commit"] for s in json.load(open(sys.argv[1]))["siblings"]}
bad = [n for n in pins if manifest.get(n) != pins[n]]
sys.exit("siblings.json disagrees with the manifest for: " + ", ".join(bad) if bad else 0)
' "$deploy/siblings.json" || die "the release's deployment and manifest disagree; nothing was installed."

  # --- an existing host's fleet domain and Codex mode --------------------------
  local amap_sandy="$deploy/amap-sandy.py" out
  local base_args=() install_args=()
  if [ -n "${AMAP_FLEET_DOMAIN_BASE:-}" ]; then
    base_args=(--base "$AMAP_FLEET_DOMAIN_BASE")
    install_args+=(--fleet-domain-base "$AMAP_FLEET_DOMAIN_BASE")
  fi
  if [ -f "$SANDY_HOME/features/amap/feature.json" ]; then
    out=$(SANDY_HOME="$SANDY_HOME" python3 "$amap_sandy" fleet-domain ${base_args[@]+"${base_args[@]}"} 2>&1) || out=""
    case "$out" in
      *"already set"*|"") ;;
      *) say "note: this host's fleet domain is not the one it would derive; nothing was changed."
         printf '%s\n' "$out"
         say "  To move it, see amap-deploy-sandy's install.sh (AMAP_MOVE_FLEET_DOMAIN=1)." ;;
    esac
  fi
  local codex_mode="${AMAP_CODEX_MODE:-}"
  if python3 "$amap_sandy" install --help | grep -q -- --codex-mode; then
    [ -n "$codex_mode" ] || codex_mode=$(default_codex_mode "$SANDY_HOME/features/amap/feature.json")
  elif [ -n "$codex_mode" ]; then
    die "release $AMAP_RELEASE does not support AMAP_CODEX_MODE; unset it or choose a later release."
  fi
  if [ -n "$codex_mode" ]; then
    say "Codex conversation mode: $codex_mode"
    install_args+=(--codex-mode "$codex_mode")
    AMAP_CODEX=1
  fi
  if [ "${AMAP_CODEX:-}" = "1" ]; then
    [ -n "$codex_row" ] || die "release $AMAP_RELEASE has no $CODEX_REPO."
    # shellcheck disable=SC2086  # five space-free fields
    checkout $codex_row
  elif [ -n "$codex_row" ]; then
    say "skipping $CODEX_REPO (set AMAP_CODEX=1 to include it)"
  fi

  # --- the manifest, the payload, the router's config and its directories -----
  say "installing the AMAP feature from $AMAP_RELEASE into $SANDY_HOME/features/amap"
  SANDY_HOME="$SANDY_HOME" python3 "$amap_sandy" install --apply ${install_args[@]+"${install_args[@]}"} \
    || die "install --apply reported a failure (FAIL above); the router was not started. Fix it, then re-run."
  local config="$SANDY_HOME/features/amap/router.json"
  [ -f "$config" ] || die "install did not write $config; see its output above."

  # --- the router ---------------------------------------------------------------
  say "building the router image"
  "$AMAP_DIR/amap-router-local/docker/build.sh" --quiet >/dev/null
  # Running, stopped, or absent: a stopped container still holds the name, so
  # run.sh would fail on it; it is started instead.
  local running
  running=$(docker container inspect -f '{{.State.Running}}' "$ROUTER_CONTAINER" 2>/dev/null) \
    || running=absent
  case "$running" in
    true)
      say "the router container $ROUTER_CONTAINER is running; it was left running."
      say "  It re-reads its config on every poll. To run the image just built:"
      say "  docker rm -f $ROUTER_CONTAINER, then re-run this script." ;;
    absent)
      say "starting the router"
      "$AMAP_DIR/amap-router-local/docker/run.sh" --config "$config" --detach >/dev/null ;;
    *)
      say "the router container $ROUTER_CONTAINER exists but is stopped; starting it"
      docker start "$ROUTER_CONTAINER" >/dev/null \
        || die "docker start $ROUTER_CONTAINER failed; read: docker logs --tail 50 $ROUTER_CONTAINER"
      say "  It runs the image it was created from. To run the image just built:"
      say "  docker rm -f $ROUTER_CONTAINER, then re-run this script." ;;
  esac

  cat <<EOF

[amap] Done. $AMAP_RELEASE is installed and the router is running.
[amap] Start agents whenever you need them, in any order:
[amap]   cd <a workspace> && sandy --start
[amap] A sandbox that was already running must be relaunched once
[amap] (sandy --stop, then sandy --start) to pick up the feature.
[amap] Check everything:  python3 $amap_sandy verify
[amap] The checkouts under $AMAP_DIR are detached at $AMAP_RELEASE.
EOF
  if [ "$codex_mode" = "unified" ]; then
    cat <<EOF
[amap] Unified Codex conversations apply to NEWLY CREATED Codex-served sandboxes.
[amap] Existing Codex sandboxes keep their state and hold; see the release
[amap] README for the operator procedure before recreating any of them.
EOF
  fi
}

main "$@"
