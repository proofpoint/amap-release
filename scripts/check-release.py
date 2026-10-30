#!/usr/bin/env python3
"""Check exact component pins and the shipped mixed-agent launcher contract.

Only --fetch and --require-published-tags contact component repositories. No Sandy, Docker, native agent,
credentials, or host configuration is used. Published tags are a separate,
explicit check so a candidate can be tested before its tags are published.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
NAMES = {"amap-connector-claude", "amap-connector-codex", "amap-deploy-sandy", "amap-router-local"}


def run(argv, **kwargs):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=120, **kwargs)
    if result.returncode:
        raise ValueError("command failed: " + shlex.join(map(str, argv)) + "\n" + result.stdout + result.stderr)
    return result.stdout.strip()


def check_mixed_launcher(path):
    source = path.read_text()
    assignment = "STATE=/opt/sandy/feature-state/amap/codex"
    if source.count(assignment) != 1:
        raise ValueError("shipped launcher's state assignment is unknown")
    with TemporaryDirectory(prefix="amap-release-contract-") as temporary:
        root = Path(temporary)
        state, outbox = root / "state", root / "outbox"
        state.mkdir()
        outbox.mkdir()
        launcher = root / "interactive-launch"
        launcher.write_text(source.replace(assignment, "STATE=" + shlex.quote(str(state)), 1))
        env = {"PATH": os.defpath, "HOME": str(root), "AMAP_OUTBOX_DIR": str(outbox)}
        values = ["argument with spaces", "$(touch never-execute)", "--no-daemon"]
        native = [sys.executable, "-I", "-c", "import json,sys;print(json.dumps(sys.argv[1:]))", *values]
        cases = 0
        for agents in ("claude,codex", "codex,claude", "claude,codex,gemini"):
            for mode in ("unified", "separate"):
                result = subprocess.run(["/bin/sh", str(launcher), *native], text=True,
                                        capture_output=True, timeout=10, cwd=root,
                                        env={**env, "SANDY_AGENT": agents, "AMAP_CODEX_CONVERSATION_MODE": mode})
                if result.returncode or json.loads(result.stdout) != values:
                    raise ValueError("mixed native pane refused or changed argv: " + result.stderr)
                cases += 1
        for agents in ("claude,codex", "codex"):
            for mode in ("", "foreign"):
                result = subprocess.run(["/bin/sh", str(launcher), *native], text=True,
                                        capture_output=True, timeout=10, cwd=root,
                                        env={**env, "SANDY_AGENT": agents, "AMAP_CODEX_CONVERSATION_MODE": mode})
                if not result.returncode or result.stdout or "unknown fleet conversation mode" not in result.stderr:
                    raise ValueError("unknown fleet mode did not refuse before native launch")
                cases += 1
        markers = [state / name for name in ("adapter-transition.json", "fresh-birth.json", "fresh-plan.json",
                   "fresh-initialization.json", "fresh-startup.json", "fresh-selection.json")]
        markers += [state.parent / ".fresh-intent-state.json", outbox / ".codex-unified-custody.json"]
        # The fixture state basename changes the parent intent's exact pathname.
        for marker in markers:
            for kind in ("file", "dangling symlink"):
                if kind == "file":
                    marker.write_text("{}")
                else:
                    marker.symlink_to(root / "absent")
                try:
                    result = subprocess.run(["/bin/sh", str(launcher), *native], text=True,
                                            capture_output=True, timeout=10, cwd=root,
                                            env={**env, "SANDY_AGENT": "claude,codex",
                                                 "AMAP_CODEX_CONVERSATION_MODE": "unified"})
                    if (not result.returncode or result.stdout
                            or "retained Codex unified ownership" not in result.stderr):
                        raise ValueError("retained ownership did not refuse: " + marker.name + " (" + kind + ")")
                finally:
                    marker.unlink()
                cases += 1
        if (root / "never-execute").exists():
            raise ValueError("native arguments were executed as shell code")
    return cases


def check_adoption(deployment, components):
    # The host verifier must import without native Codex dependencies, also on Python 3.9.
    run([sys.executable, "-I", "-S", "-c",
         "import sys; sys.path.insert(0,sys.argv[1]); "
         "import codex_adoption,codex_unified_status,codex_transition; "
         "assert 'amap_codex.config' not in sys.modules", str(deployment)], cwd=components)
    if sys.version_info < (3, 11):
        return "host adoption modules imported in isolation; runtime fixtures require Python 3.11+"
    # These are the pinned deployment's actual Config/Journal fixtures and mutation matrix.
    # They use no native agent or Docker and prove both startup and host-verify refusals.
    temporary = str(Path("/tmp").resolve())
    environment = {**os.environ, "PYTHONPATH": str(deployment), "TMPDIR": temporary,
                   "AMAP_TEST_TMPDIR": temporary, "PYTHONDONTWRITEBYTECODE": "1",
                   "AMAP_ROUTER_REPO": str(components / "amap-router-local"),
                   "AMAP_CONNECTOR_REPO": str(components / "amap-connector-claude"),
                   "AMAP_CODEX_CONNECTOR_REPO": str(components / "amap-connector-codex")}
    for pattern in ("test_codex_transition.py", "test_codex_unified_status.py", "test_sandbox_list_read.py"):
        run([sys.executable, "-m", "unittest", "discover", "-s", str(deployment / "tests"),
             "-p", pattern, "-q"], cwd=deployment, env=environment)
    run([sys.executable, "-m", "unittest", "-q",
         "test_peer_lane.VerifyEndToEndTest.test_install_asks_sandy_for_print_state_once",
         "test_peer_lane.VerifyEndToEndTest.test_verify_asks_sandy_for_print_state_once"],
        cwd=deployment / "tests", env=environment)
    return "pinned transition, adoption/verify mutation, revalidation and inventory-read suites passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--components-dir", type=Path, required=True)
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--require-published-tags", action="store_true")
    args = parser.parse_args()
    args.components_dir = args.components_dir.resolve()
    match = re.search(r"^LATEST_RELEASE=(amap-[0-9]{4}-[0-9]{2}-[0-9]{2}(?:\.[1-9][0-9]*)?)$", (ROOT / "install.sh").read_text(), re.M)
    if match is None:
        raise ValueError("installer's latest release is unknown")
    label = match.group(1)
    manifest = json.loads((ROOT / "releases" / label / (label + ".json")).read_text())
    records = manifest["repositories"]
    if manifest.get("release") != label or len(records) != len(NAMES) or {r["name"] for r in records} != NAMES:
        raise ValueError("latest manifest does not name the exact component set")
    for record in records:
        name = record["name"]
        url = record["remote_url"]
        if url not in {"https://github.com/proofpoint/" + name, "https://github.com/proofpoint/" + name + ".git"}:
            raise ValueError("unexpected component remote: " + name)
        if record.get("tag") != label or any(not re.fullmatch("[a-f0-9]{40}", record[key])
                                             for key in ("commit", "tag_object")):
            raise ValueError("component tag or full object pin is invalid: " + name)
        repository = args.components_dir / name
        if args.fetch:
            if repository.exists():
                raise ValueError("--fetch requires a new component directory: " + str(repository))
            repository.mkdir(parents=True)
            run(["git", "init", str(repository)])
            run(["git", "-C", str(repository), "fetch", "--no-tags", "--depth=1", url, record["commit"]])
            run(["git", "-C", str(repository), "checkout", "--detach", "FETCH_HEAD"])
        actual = run(["git", "-C", str(repository), "rev-parse", "HEAD"])
        if actual != record["commit"]:
            raise ValueError("component checkout differs from manifest: " + name)
        if args.require_published_tags:
            ref = "refs/tags/" + record["tag"]
            rows = run(["git", "ls-remote", "--tags", url, ref, ref + "^{}"]).splitlines()
            observed = {line.split()[1]: line.split()[0] for line in rows}
            if observed.get(ref) != record["tag_object"] or observed.get(ref + "^{}") != record["commit"]:
                raise ValueError("published annotated tag differs or is unavailable: " + name)
    expected = {r["name"]: r["commit"] for r in records if r["name"] != "amap-deploy-sandy"}
    deployment = args.components_dir / "amap-deploy-sandy"
    siblings = json.loads((deployment / "siblings.json").read_text())["siblings"]
    if {s["name"]: s["commit"] for s in siblings} != expected:
        raise ValueError("deployment siblings.json differs from the release manifest")
    cases = check_mixed_launcher(deployment / "payload/codex/interactive-launch")
    adoption = check_adoption(deployment, args.components_dir.resolve())
    print(label + ": exact component checkouts and sibling pins agree; " + str(cases) + " launcher cases passed")
    print("Adoption: " + adoption)
    print("Published annotated tags: " + ("verified" if args.require_published_tags else "not checked; required before promotion"))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        sys.exit("FAIL: " + str(exc))
