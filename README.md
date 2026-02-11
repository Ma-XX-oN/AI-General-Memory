# AI General Memory <!-- omit in toc -->

Shared knowledge files for Claude Code and Codex.

- [Contents](#contents)
- [Installation](#installation)
- [Claude Code](#claude-code)
  - [Existing `~/.claude/` directory](#existing-claude-directory)
  - [Fresh machine (no existing `~/.claude/`)](#fresh-machine-no-existing-claude)
- [Codex](#codex)
  - [Resolve `CODEX_DIR`](#resolve-codex_dir)
  - [Existing `CODEX_DIR` directory](#existing-codex_dir-directory)
  - [Fresh machine (no existing `CODEX_DIR`)](#fresh-machine-no-existing-codex_dir)
  - [How project-specific Codex memory works](#how-project-specific-codex-memory-works)
- [Adding new knowledge files](#adding-new-knowledge-files)

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

When `$CODEX_HOME` is not set, Codex uses defaults automatically.

### Resolve `CODEX_DIR`

POSIX shells (Linux/macOS):

```bash
CODEX_DIR="${CODEX_HOME:-${XDG_CONFIG_HOME:-$HOME/.codex}}"
```

Git Bash on Windows:

```bash
CODEX_DIR="${CODEX_HOME:-$(cygpath "$USERPROFILE")/.codex}"
```

### Existing `CODEX_DIR` directory

```bash
cd "$CODEX_DIR"
git init
git remote add origin https://github.com/Ma-XX-oN/AI-General-Memory.git
git fetch origin
git checkout -b master origin/master
```

### Fresh machine (no existing `CODEX_DIR`)

```bash
git clone https://github.com/Ma-XX-oN/AI-General-Memory.git "$CODEX_DIR/"
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
