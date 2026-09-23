# CI request and result contract

AI-General-Memory uses an explicit CI request instead of running expensive validation on every development push.

## Development cycle

1. Work on an issue branch using `x.y.z-issue.<issue>.<iteration>`.
2. Establish the issue version in `scripts/AI_transcript_version.py` before substantive issue work.
3. Make ordinary source/documentation commits without requesting hosted CI.
4. Run focused checks locally while developing.
5. When the complete candidate is ready, set `.ci/run-ci-request` to the exact authoritative development version and push that change.
6. GitHub Actions validates that exact request commit.

The request value and authoritative version must match exactly.

## Local validation

The same repository-owned contract invoked by Actions is directly runnable from a clean clone:

```text
python scripts/ci_contract.py preflight
python scripts/ci_contract.py matrix
python scripts/ci_contract.py run \
  --environment ubuntu-node22-python313 \
  --result /path/outside/repository/result.json
```

The required environment is declared in `.ci/test-matrix.json`. The current required environment is Ubuntu with Node 22 and Python 3.13. `ci_contract.py` records the actual OS and runtime versions and refuses to treat a mismatched environment as a valid result.

The environment command executes `scripts/ci_environment.py`, which owns the AI-transcript/Core validation list formerly embedded in Actions YAML. It includes:

- pinned AIConversationCore gitlink/submodule/worker identity;
- AI-transcript/Core version identity;
- the real pull helper from an uninitialized local clone;
- Python syntax;
- pre-Phase-6 historical presentation parity;
- canonical production parity;
- turn-ID and record-number projection;
- leading Claude system-context regression;
- Codex revision-history regression;
- Codex user-context CLI acceptance;
- the portable AI-transcript regression subset;
- the pinned Core regression suite; and
- diff hygiene.

Independent validation gates continue after another independent gate fails so one failure does not hide the rest of the initial RED surface.

## Clean checkout prerequisite

A candidate is valid only from a clean checkout of its exact commit. `preflight` and every environment run require:

- `.ci/run-ci-request` equals the authoritative version;
- no tracked, untracked, staged, or submodule working-tree changes; and
- the exact current commit is recorded in every result.

Result JSON belongs outside the repository so recording validation evidence cannot dirty the checkout being validated.

## Infrastructure and prerequisites

Initializing the pinned submodule and installing required Python presentation dependencies are prerequisites. If network, credentials, package service, runner allocation, required OS, or runtime availability prevents a prerequisite from completing, the result is **INCOMPLETE**, not a source failure.

A GitHub Actions system failure before tests execute is likewise not `CI-FAIL`. Re-run the same workflow/jobs against the same commit; do not consume a new issue iteration merely to retry infrastructure.

The pull-helper regression itself does not require GitHub network access. The repository-owned runner constructs local Git remotes and rewrites only the pinned Core transport URL to the already checked-out submodule, while exercising the real `pull-AI-General-Memory.sh` behaviour.

## Matrix finalization and `--tag`

Aggregate required result records with:

```text
python scripts/ci_contract.py finalize --results-dir /path/to/results
```

Adding `--tag` authorizes tag creation only after matrix completeness and identity are proven:

```text
python scripts/ci_contract.py finalize \
  --results-dir /path/to/results \
  --tag
```

`--tag` never bypasses a missing required OS/runtime result. `--push` additionally publishes the tag and requires `--tag`.

Result semantics are:

- **PASS** — every required environment reported for the same commit/version and every required validation gate passed. With `--tag`, create `v<version>`.
- **FAIL** — the complete required matrix reported and at least one genuine executed validation gate failed, with no required environment incomplete. With `--tag`, create `v<version>-CI-FAIL`.
- **INCOMPLETE** — a required result is absent or prerequisites/infrastructure prevented valid execution. Emit warnings and create no result tag.

PASS and `CI-FAIL` tags are immutable landmarks. Once either result tag exists for an issue iteration, the opposite result cannot be created and a different candidate requires the next issue iteration.

## GitHub Actions boundary

`.github/workflows/ci.yml` is orchestration only:

1. verify the explicit request and clean checkout;
2. load `.ci/test-matrix.json`;
3. execute every required matrix environment with `fail-fast: false`;
4. upload machine-readable environment results; and
5. run one finalizer after all required jobs have reported.

Validation jobs have read-only repository permissions. Only the finalizer has contents-write permission, and only for the immutable result tag. Tests do not depend on GitHub-specific metadata except the thin orchestration/provenance layer.
