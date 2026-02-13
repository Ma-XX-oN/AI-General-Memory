# Build Issues Playbook

Use this checklist when a build or link failure looks environment/toolchain-related.

## 1) Sanity-check toolchain identity

- Confirm compiler/linker/archiver are from one family.
- Confirm PATH precedence points to the intended toolchain bins first.
- Confirm generator/config model matches the build tree (single-config vs multi-config).

## 2) Validate project-config source of truth

- Check project config first (`.vscode/settings.json`, `CMakePresets.json`, `CMakeUserPresets.json`, toolchain file).
- Mirror those settings exactly before trying manual overrides.

## 3) Diagnose linker mismatch symptoms quickly

Treat these as mixed-toolchain indicators first:

- file format not recognized
- wrong machine/architecture
- archive/index incompatibility
- unresolved runtime symbols that suggest different runtime/stdlib families

## 4) Fast recovery path

- Stop incremental retries.
- Create a fresh build directory.
- Reconfigure from project settings/presets.
- Rebuild.
- Re-run target tests.

## 5) Persistence rule

- If a project has unique prerequisites (for example PATH prefixes), store them in that project's `CODEX.md`.
- Keep cross-project lessons in `~/.codex/CODEX.md`.
