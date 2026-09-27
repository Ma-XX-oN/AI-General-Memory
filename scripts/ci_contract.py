#!/usr/bin/env python3
"""Repository-owned CI request, execution, result, and tagging contract."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys
import tempfile
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / ".ci" / "ci-config.json"
REQUEST_PATH = ROOT / ".ci" / "run-ci-request"
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+-issue\.\d+\.\d+$")


class CiContractError(RuntimeError):
  """Raised when a CI contract invariant is violated."""


def load_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
  """Load the CI configuration and its committed environment matrix."""
  config = json.loads(path.read_text(encoding="utf-8"))
  matrix_path = config.get("matrixPath")
  if matrix_path:
    matrix_data = json.loads((ROOT / matrix_path).read_text(encoding="utf-8"))
    config["environments"] = matrix_data["environments"]
  return config


def read_version(config: dict[str, Any], root: Path = ROOT) -> str:
  """Read and validate the authoritative issue-development version."""
  spec = config["version"]
  text = (root / spec["path"]).read_text(encoding="utf-8")
  kind = spec["kind"]
  if kind == "plain":
    value = text.strip()
  elif kind == "json":
    value: Any = json.loads(text)
    for key in spec["key"].split("."):
      value = value[key]
    value = str(value)
  elif kind == "regex":
    match = re.search(spec["pattern"], text, re.MULTILINE)
    if not match:
      raise CiContractError(f"Version pattern did not match {spec['path']}")
    value = match.group(1)
  else:
    raise CiContractError(f"Unknown version source kind: {kind}")
  if not VERSION_RE.fullmatch(value):
    raise CiContractError(f"Development version is invalid: {value}")
  return value


def read_request(root: Path = ROOT) -> str:
  """Read and validate the explicit CI request version."""
  value = (root / ".ci" / "run-ci-request").read_text(encoding="utf-8").strip()
  if not VERSION_RE.fullmatch(value):
    raise CiContractError(f"CI request version is invalid: {value}")
  return value


def git(
  root: Path,
  *args: str,
  check: bool = True,
) -> subprocess.CompletedProcess[str]:
  """Run Git in one repository checkout."""
  return subprocess.run(
    ["git", *args],
    cwd=root,
    check=check,
    text=True,
    capture_output=True,
  )


def head_sha(root: Path = ROOT) -> str:
  """Return the exact current commit SHA."""
  return git(root, "rev-parse", "HEAD").stdout.strip()


def assert_clean_checkout(root: Path = ROOT) -> None:
  """Require tracked and untracked repository state to match HEAD exactly."""
  status = git(
    root,
    "status",
    "--porcelain=v1",
    "--untracked-files=all",
    "--ignore-submodules=none",
  ).stdout
  if status:
    raise CiContractError(
      "CI requires a clean checkout; working-tree changes were detected:\n" + status
    )


def validate_request(
  config: dict[str, Any],
  root: Path = ROOT,
) -> tuple[str, str]:
  """Require request/version equality and a clean exact candidate checkout."""
  version = read_version(config, root)
  request = read_request(root)
  if request != version:
    raise CiContractError(
      f".ci/run-ci-request ({request}) does not match authoritative version ({version})"
    )
  assert_clean_checkout(root)
  return version, head_sha(root)


def matrix(config: dict[str, Any]) -> dict[str, Any]:
  """Return the committed environment matrix in Actions-compatible form."""
  include = []
  for env in config["environments"]:
    include.append({
      "id": env["id"],
      "runner": env["runner"],
      "required": bool(env.get("required", True)),
    })
  return {"include": include}


def find_environment(config: dict[str, Any], env_id: str) -> dict[str, Any]:
  """Return one declared environment by stable identifier."""
  for env in config["environments"]:
    if env["id"] == env_id:
      return env
  raise CiContractError(f"Unknown CI environment: {env_id}")


def actual_runtime() -> dict[str, str]:
  """Record the actual operating system and primary runtime versions."""
  values = {
    "os": platform.platform(),
    "python": sys.version.split()[0],
  }
  for name, command in (
    ("node", ["node", "--version"]),
    ("git", ["git", "--version"]),
  ):
    try:
      result = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
      )
      values[name] = (result.stdout or result.stderr).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
      values[name] = f"unavailable: {exc}"
  return values


def environment_mismatches(env: dict[str, Any]) -> list[str]:
  """Return required OS/runtime mismatches that make validation incomplete."""
  warnings = []
  expected_os = str(env.get("os", "")).lower()
  actual_os = platform.system().lower()
  os_matches = {
    "ubuntu": actual_os == "linux",
    "linux": actual_os == "linux",
    "windows": actual_os == "windows",
    "macos": actual_os == "darwin",
  }
  if expected_os and not os_matches.get(expected_os, False):
    warnings.append(f"required OS {expected_os}, actual {platform.system()}")

  runtimes = env.get("runtimes", {})
  expected_python = str(runtimes.get("python", ""))
  actual_python = f"{sys.version_info.major}.{sys.version_info.minor}"
  if expected_python and actual_python != expected_python:
    warnings.append(f"required Python {expected_python}, actual {actual_python}")

  expected_node = str(runtimes.get("node", ""))
  if expected_node:
    try:
      node_text = subprocess.run(
        ["node", "--version"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
      ).stdout.strip().lstrip("v")
      actual_node = node_text.split(".", 1)[0]
      if actual_node != expected_node:
        warnings.append(f"required Node {expected_node}, actual {node_text}")
    except (OSError, subprocess.CalledProcessError) as exc:
      warnings.append(f"required Node {expected_node} unavailable: {exc}")
  return warnings


def expand_value(value: str, root: Path, temp: Path) -> str:
  """Expand stable repository and temporary-directory placeholders."""
  return value.replace("{root}", str(root)).replace("{temp}", str(temp))


def run_step(
  step: dict[str, Any],
  root: Path,
  temp: Path,
) -> tuple[int, str, str]:
  """Run one committed CI step without hiding its command or return code."""
  raw_command = step["command"]
  cwd_value = expand_value(step.get("cwd", "."), root, temp)
  cwd = Path(cwd_value)
  if not cwd.is_absolute():
    cwd = root / cwd
  env = dict(os.environ)
  for key, value in step.get("env", {}).items():
    env[key] = expand_value(value, root, temp)

  if isinstance(raw_command, str):
    command = expand_value(raw_command, root, temp)
    completed = subprocess.run(command, cwd=cwd, env=env, shell=True, text=True)
    rendered = command
  else:
    command = [expand_value(str(item), root, temp) for item in raw_command]
    completed = subprocess.run(command, cwd=cwd, env=env, text=True)
    rendered = shlex.join(command)
  return completed.returncode, rendered, step.get("kind", "validation")


def write_result(path: Path, result: dict[str, Any]) -> None:
  """Write one machine-readable environment result outside the checkout."""
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


def run_environment(
  config: dict[str, Any],
  env_id: str,
  result_path: Path,
  root: Path = ROOT,
) -> int:
  """Execute every independent gate for one declared validation environment."""
  version, sha = validate_request(config, root)
  env_config = find_environment(config, env_id)
  result: dict[str, Any] = {
    "schema": 1,
    "environment": env_id,
    "required": bool(env_config.get("required", True)),
    "declared": {
      key: env_config[key]
      for key in ("runner", "os", "runtimes")
      if key in env_config
    },
    "version": version,
    "commit": sha,
    "status": "PASS",
    "runtime": actual_runtime(),
    "warnings": [],
    "steps": [],
  }

  mismatches = environment_mismatches(env_config)
  if mismatches:
    result["status"] = "INCOMPLETE"
    result["warnings"].extend(mismatches)
    write_result(result_path, result)
    return 2

  saw_failure = False
  saw_incomplete = False
  with tempfile.TemporaryDirectory(prefix="repo-ci-") as temp_name:
    temp = Path(temp_name)
    for step in env_config.get("steps", []):
      try:
        rc, rendered, kind = run_step(step, root, temp)
      except OSError as exc:
        rc = 2
        rendered = str(step.get("command"))
        kind = step.get("kind", "validation")
        result["warnings"].append(str(exc))
      result["steps"].append({
        "name": step["name"],
        "command": rendered,
        "kind": kind,
        "returncode": rc,
      })
      if rc == 0:
        continue
      if rc == 2 or kind == "prerequisite":
        saw_incomplete = True
        if kind == "prerequisite":
          break
        continue
      saw_failure = True
      if kind == "setup":
        break

  if saw_incomplete:
    result["status"] = "INCOMPLETE"
    exit_code = 2
  elif saw_failure:
    result["status"] = "FAIL"
    exit_code = 1
  else:
    exit_code = 0
  write_result(result_path, result)
  return exit_code


def collect_results(results_dir: Path) -> list[dict[str, Any]]:
  """Collect valid result records from downloaded/local result artifacts."""
  results = []
  if not results_dir.exists():
    return results
  for path in sorted(results_dir.rglob("*.json")):
    try:
      value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
      continue
    if value.get("schema") == 1 and "environment" in value:
      results.append(value)
  return results


def evaluate_results(
  config: dict[str, Any],
  results: list[dict[str, Any]],
  version: str,
  sha: str,
) -> tuple[str, str | None, list[str]]:
  """Determine PASS, FAIL, or INCOMPLETE only from a complete matching matrix."""
  required = {
    env["id"] for env in config["environments"] if env.get("required", True)
  }
  configured = {env["id"] for env in config["environments"]}
  by_env: dict[str, dict[str, Any]] = {}
  for result in results:
    env_id = result.get("environment")
    if env_id not in configured:
      raise CiContractError(f"Unknown CI result environment: {env_id}")
    if env_id in by_env:
      raise CiContractError(f"Duplicate CI result for environment: {env_id}")
    if result.get("version") != version:
      raise CiContractError(
        f"{env_id} reported version {result.get('version')}, expected {version}"
      )
    if result.get("commit") != sha:
      raise CiContractError(
        f"{env_id} reported commit {result.get('commit')}, expected {sha}"
      )
    by_env[env_id] = result

  warnings: list[str] = []
  missing = sorted(required - by_env.keys())
  if missing:
    warnings.append("Missing required CI result(s): " + ", ".join(missing))
    return "INCOMPLETE", None, warnings

  incomplete = sorted(
    env_id for env_id in required if by_env[env_id].get("status") == "INCOMPLETE"
  )
  if incomplete:
    warnings.append("Required CI environment incomplete: " + ", ".join(incomplete))
    return "INCOMPLETE", None, warnings

  unexpected = sorted(
    env_id for env_id in required
    if by_env[env_id].get("status") not in {"PASS", "FAIL"}
  )
  if unexpected:
    warnings.append("Required CI result has unknown status: " + ", ".join(unexpected))
    return "INCOMPLETE", None, warnings

  failed = sorted(
    env_id for env_id in required if by_env[env_id].get("status") == "FAIL"
  )
  if failed:
    return "FAIL", f"v{version}-CI-FAIL", warnings
  return "PASS", f"v{version}", warnings


def tag_target(root: Path, tag: str) -> str | None:
  """Resolve a local lightweight/annotated tag to its target commit."""
  existing = git(root, "rev-parse", "-q", "--verify", f"refs/tags/{tag}", check=False)
  if existing.returncode:
    return None
  return git(root, "rev-list", "-n", "1", tag).stdout.strip()


def ensure_result_tag_available(
  root: Path,
  version: str,
  requested_tag: str,
  sha: str,
) -> bool:
  """Enforce one immutable PASS/FAIL result per development iteration."""
  normal = f"v{version}"
  failed = f"v{version}-CI-FAIL"
  for tag in (normal, failed):
    target = tag_target(root, tag)
    if target is None:
      continue
    if tag != requested_tag:
      raise CiContractError(
        f"Development iteration {version} already has result tag {tag}; "
        "increment the issue iteration instead of creating another result"
      )
    if target != sha:
      raise CiContractError(
        f"Tag {tag} already exists at {target}; refusing to move it to {sha}"
      )
    return False
  return True


def create_tag(root: Path, version: str, tag: str, sha: str, push: bool) -> None:
  """Create and optionally publish one immutable annotated result tag."""
  if ensure_result_tag_available(root, version, tag, sha):
    git(root, "tag", "-a", tag, sha, "-m", tag)
  if push:
    git(root, "push", "origin", f"refs/tags/{tag}")


def finalize(
  config: dict[str, Any],
  results_dir: Path,
  do_tag: bool,
  push: bool,
  root: Path = ROOT,
) -> int:
  """Aggregate a complete matrix and optionally publish its immutable result tag."""
  version, sha = validate_request(config, root)
  outcome, tag, warnings = evaluate_results(
    config,
    collect_results(results_dir),
    version,
    sha,
  )
  for warning in warnings:
    print(f"WARNING: {warning}", file=sys.stderr)
    if os.environ.get("GITHUB_ACTIONS") == "true":
      print(f"::warning::{warning}", file=sys.stderr)
  print(f"CI outcome: {outcome}")
  if tag:
    print(f"Result tag: {tag}")
  if outcome == "INCOMPLETE":
    return 2
  if push and not do_tag:
    raise CiContractError("--push requires --tag")
  if do_tag and tag:
    create_tag(root, version, tag, sha, push)
  return 0 if outcome == "PASS" else 1


def build_parser() -> argparse.ArgumentParser:
  """Build the stable local/Actions command-line contract."""
  parser = argparse.ArgumentParser()
  sub = parser.add_subparsers(dest="command", required=True)
  sub.add_parser("matrix")
  sub.add_parser("preflight")

  run = sub.add_parser("run")
  run.add_argument("--environment", required=True)
  run.add_argument("--result", required=True)

  fin = sub.add_parser("finalize")
  fin.add_argument("--results-dir", required=True)
  fin.add_argument("--tag", action="store_true")
  fin.add_argument("--push", action="store_true")
  return parser


def main() -> int:
  """Execute one CI contract operation."""
  args = build_parser().parse_args()
  config = load_config()
  try:
    if args.command == "matrix":
      print(json.dumps(matrix(config), separators=(",", ":")))
      return 0
    if args.command == "preflight":
      version, sha = validate_request(config)
      print(json.dumps({"version": version, "commit": sha}))
      return 0
    if args.command == "run":
      return run_environment(config, args.environment, Path(args.result))
    if args.command == "finalize":
      return finalize(config, Path(args.results_dir), args.tag, args.push)
  except CiContractError as exc:
    print(f"CI contract error: {exc}", file=sys.stderr)
    return 2
  raise AssertionError("unreachable")


if __name__ == "__main__":
  raise SystemExit(main())
