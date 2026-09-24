# CI request and result contract

AI-General-Memory uses RepoWorkflow as the authoritative repository workflow engine. Expensive issue-development validation is explicitly request-gated instead of running on every development push.

## Development cycle

1. Work on an issue branch using `x.y.z-issue.<issue>.<iteration>`.
2. Establish the issue version in `scripts/AI_transcript_version.py` before substantive issue work.
3. Make ordinary source/documentation commits without requesting hosted CI.
4. Run focused checks while developing.
5. When the complete candidate is ready, set `.ci/run-ci-request` to the exact authoritative development version.
6. Run the direct RepoWorkflow verification path against that exact request candidate before terminalizing it remotely.
7. Publish the same candidate SHA so the canonical GitHub adapter can perform hosted policy, preparation, validation, and finalization.

The request value and authoritative version must match exactly.

## RepoWorkflow configuration

Repository-specific workflow facts live in:

- `.ci/repoworkflow.json` — version command, authoritative remote, required environments, and repository validation command;
- `.ci/github.json` — GitHub runner/toolchain projection; and
- `.ci/branch-policy.json` — branch ancestry and integration-target policy.

The shared engine is pinned as the `RepoWorkflow` Git submodule. `.github/workflows/ci.yml` must remain byte-identical to the canonical adapter at `RepoWorkflow/templates/github/ci.yml`.

## Local authoritative verification

From a clean, complete checkout on the named issue branch, with `.ci/run-ci-request` matching the current development version, run:

```text
python RepoWorkflow/repo_workflow.py verify
```

`verify` enforces repository policy, branch policy, exact-candidate/request eligibility, authoritative terminal-tag state, required environment execution, mutation detection, and result aggregation. It does not create a result tag unless explicitly invoked with tagging authorization.

The required AIGM environment is declared in `.ci/repoworkflow.json` as Linux with Node 22 and Python 3.13. GitHub runner/toolchain provisioning is derived from those declared capabilities rather than assumed from the runner image.

## AIGM validation boundary

`scripts/repoworkflow_validate.py` is the single repository-owned validation hook exposed to RepoWorkflow. It preserves AIGM-specific prerequisites and validation semantics:

- recursively initialize the pinned submodules;
- install the required `colorama` and `regex` presentation dependencies;
- run the RepoWorkflow adoption/invariant regression; and
- run `scripts/ci_environment.py`.

Submodule, package-service, network, credential, required-platform, or required-runtime failures are prerequisites and produce exit 2 so RepoWorkflow classifies the environment as **INCOMPLETE**, not a source failure.

`scripts/ci_environment.py` remains the authoritative AIGM/Core validation surface. It covers:

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

## Candidate and result semantics

RepoWorkflow requires a clean, complete checkout of the exact candidate. `.ci/run-ci-request` must match the authoritative version, validation must not modify repository state, and every structured result is bound to the same version and commit.

Result semantics are:

- **PASS** — every required environment reported for the same commit/version and every required validation gate passed; terminal tag `v<version>`.
- **FAIL** — the complete required matrix reported and at least one genuine executed validation gate failed; terminal tag `v<version>-CI-FAIL`.
- **INCOMPLETE** — prerequisites, infrastructure, platform/runtime availability, or missing required results prevented a valid complete result; no terminal tag.

PASS and `CI-FAIL` tags are immutable landmarks. Once either exists for an issue iteration, a changed candidate must advance to the next issue iteration.

## GitHub Actions boundary

The canonical `.github/workflows/ci.yml` is only the GitHub adapter. It performs:

1. shared repository and branch policy checks;
2. explicit request detection through `RepoWorkflow/repo_workflow.py github-request`;
3. candidate preparation;
4. capability-driven Node/Python provisioning;
5. required matrix fan-out to the repository-owned validation hook;
6. structured result transport; and
7. one finalizer that aggregates results and publishes the immutable result tag.

Validation remains repository-read-only. The canonical adapter's narrowly scoped write permissions are used only by RepoWorkflow's generated-artifact/final-result machinery; AIGM currently declares no committed generated artifacts.

Do not add repository-specific workflow lifecycle logic to `ci.yml`. Shared lifecycle behavior belongs in RepoWorkflow; AIGM-specific validation belongs in `scripts/repoworkflow_validate.py` and `scripts/ci_environment.py`.
