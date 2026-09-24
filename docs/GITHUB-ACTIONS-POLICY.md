# GitHub Actions Policy

AI-General-Memory uses RepoWorkflow as the shared authority for GitHub Actions repository policy. GitHub Actions exist to validate checked-in repository state and publish immutable workflow results; they are not a remote editor for AI-transcript source, tests, documentation, or dependency pins.

## Permanent workflow set

The maintained repository workflow is:

- `.github/workflows/ci.yml` — the byte-identical canonical RepoWorkflow GitHub adapter.

Repository policy is enforced by:

```text
python RepoWorkflow/repo_workflow.py repository-policy
```

The canonical adapter invokes that policy automatically before any expensive requested validation. Repository-specific lifecycle forks and undeclared workflow files fail policy rather than relying on convention.

## Responsibility boundary

RepoWorkflow owns common workflow mechanics and invariants, including:

- explicit `.ci/run-ci-request` gating;
- repository and branch policy;
- exact-candidate and clean-checkout guards;
- declared capability projection into GitHub runner toolchains;
- PASS / FAIL / INCOMPLETE aggregation;
- mutation detection; and
- immutable terminal result tags.

AI-General-Memory owns its repository facts and validation commands in `.ci/repoworkflow.json`, `.ci/github.json`, `.ci/branch-policy.json`, `scripts/workflow_version.py`, `scripts/repoworkflow_validate.py`, and `scripts/ci_environment.py`.

## Repository writes

Validation commands must remain read-only with respect to the checked-out repository. AIGM declares no committed generated artifacts. The canonical adapter's write-capable phases are restricted to RepoWorkflow's shared generated-artifact/final-result machinery; for AIGM the terminal write is the immutable result tag created only after complete aggregation.

Do not add direct `git add`, `git commit`, `git push`, or mutating GitHub/cURL API commands to repository-specific validation. Do not copy shared lifecycle logic into project scripts or workflow YAML.

## Temporary verification workflows

Issue-specific verification workflows are not part of maintained repository state. When a migration requires an isolated hosted harness, keep it on a disposable helper branch and have it check out the immutable candidate SHA under test. The candidate itself must continue to satisfy canonical repository policy without the helper workflow.

## Infrastructure failures

A runner-allocation, network, credential, package-service, required-platform, or required-runtime failure is not a source CI failure. Required prerequisites must return the RepoWorkflow INCOMPLETE classification rather than manufacture a `CI-FAIL` result.
