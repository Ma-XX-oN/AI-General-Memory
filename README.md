# AI General Memory

Shared knowledge files for Claude Code and Codex.

## Contents

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Global instructions and lessons for Claude Code |
| `CODEX.md` | Global instructions and lessons for Codex |
| `AGENTS.md` | Project-level bootstrap template for Codex projects |
| `regex-patterns.md` | Reusable regex patterns referenced from CLAUDE.md / CODEX.md |
| `.gitignore` | Deny-all with explicit exceptions for knowledge files |

## Installation

This repo is designed to be used from existing tool directories (`~/.claude/`,
`$CODEX_HOME`) or as a central source repo with copied/synced files.

Since `git clone` refuses to clone into a non-empty directory, initialize git
in place when the directory already exists.

## Claude Code

Claude Code automatically loads `~/.claude/CLAUDE.md` into every project.

### Existing `~/.claude/` directory

```bash
cd ~/.claude
git init
git remote add origin https://github.com/Ma-XX-oN/AI-General-Memory.git
git fetch origin
git checkout -b master origin/master
```

### Fresh machine (no existing `~/.claude/`)

```bash
git clone https://github.com/Ma-XX-oN/AI-General-Memory.git ~/.claude/
```

## Codex

Codex global memory is stored at `$CODEX_HOME/CODEX.md`.

When `$CODEX_HOME` is not set, Codex uses these defaults automatically:

- Linux/macOS: `~/.codex`
- Windows cmd: `%USERPROFILE%\.codex`
- Windows PowerShell: `$env:USERPROFILE\.codex`

### Existing `$CODEX_HOME` directory

```bash
cd "${CODEX_HOME:-$HOME/.codex}"
git init
git remote add origin https://github.com/Ma-XX-oN/AI-General-Memory.git
git fetch origin
git checkout -b master origin/master
```

### Fresh machine (no existing `$CODEX_HOME`)

```bash
git clone https://github.com/Ma-XX-oN/AI-General-Memory.git "${CODEX_HOME:-$HOME/.codex}/"
```

### How project-specific Codex memory works

1. Keep cross-project lessons in `$CODEX_HOME/CODEX.md`.
2. Copy this repo's `AGENTS.md` into each project root.
3. Put project-specific rules in `<project>/CODEX.md`.

## Adding new knowledge files

1. Create the file in the repo.
2. Add a `!filename` entry to `.gitignore`.
3. Reference the file from `CLAUDE.md`, `CODEX.md`, or both.
4. Stage, commit, and push.
