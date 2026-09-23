# GitHub Actions Policy

GitHub Actions in AI-General-Memory exist to validate checked-in repository
state and publish immutable CI result tags.  They are not a remote editor for
AI-transcript source, tests, documentation, or dependency pins.

## Permanent workflow set

Maintained repository lines may contain only these workflow paths:

- `.github/workflows/ci.yml` — explicit request-gated repository CI and result
  tag publication.
- `.github/workflows/ai-transcript-core-parity.yml` — optional read-only
  AI-transcript/Core integration validation on maintained integration lines.
- `.github/workflows/ai-transcript-codex-user-context.yml` — optional read-only
  Codex CLI acceptance validation on maintained integration lines.

`ci.yml` is required on the default line.  The two AI-transcript validation
workflows are optional and may remain only where they perform real validation;
legacy wrappers that merely fail and redirect to `ci.yml` are obsolete.

Issue-specific, temporary, migration, repair, patch, RED/GREEN application,
instrumentation, or other one-shot workflows are prohibited.  Development
changes must be made through a normal checked-out working tree or the GitHub
repository API/connector, not by an Action that rewrites and commits project
files.

## Repository-write exception

The default-line CI may receive `contents: write` only in its finalization job,
and only to publish the tested result tag through:

`python scripts/ci_contract.py finalize ... --tag --push`

The workflow must not run direct `git add`, `git commit`, or `git push` commands,
or direct mutating GitHub/cURL API calls.  AI-transcript validation workflows
must remain read-only and must not mutate repository state.

## Enforcement

`scripts/check_actions_policy.py` enforces the workflow allow-list and write
restrictions.  `tests/test_actions_policy.py` supplies positive and negative
regression coverage, including the actual checked-out workflow set.

The permanent CI workflow is triggered by changes under `.github/workflows/**`
and by changes to the policy checker/tests.  Its lightweight Linux policy job
always runs for those changes.  The full validation matrix remains explicitly
request-gated: it proceeds only when `.ci/run-ci-request` changed in the push or
when CI was manually dispatched.

An in-repository check cannot prevent GitHub from registering or scheduling a
brand-new unauthorized workflow from the same commit before another workflow
reports the policy failure.  Repository rulesets/review controls are the only
way to prevent that first scheduling event entirely.  The repository guard
nevertheless makes accidental violations deterministic and keeps maintained
write paths behind the policy check.

Historical workflow runs are separate GitHub Actions metadata.  Purging obsolete
run history does not rewrite Git history or change commit SHAs.
