# AI General Memory <!-- omit in toc -->

Shared knowledge files for Claude Code and Codex.

- [Purpose](#purpose)
- [Contents](#contents)
- [Claude Code](#claude-code)
  - [How to Install For Claude Code](#how-to-install-for-claude-code)
    - [Resolve `CLAUDE_DIR`](#resolve-claude_dir)
    - [Existing `CLAUDE_DIR` directory](#existing-claude_dir-directory)
    - [Fresh machine (no existing `CLAUDE_DIR`)](#fresh-machine-no-existing-claude_dir)
  - [How global and project-specific Claude Code memory works](#how-global-and-project-specific-claude-code-memory-works)
- [Codex](#codex)
  - [How to Install for Codex](#how-to-install-for-codex)
    - [Resolve `CODEX_DIR`](#resolve-codex_dir)
    - [Existing `CODEX_DIR` directory](#existing-codex_dir-directory)
    - [Fresh machine (no existing `CODEX_DIR`)](#fresh-machine-no-existing-codex_dir)
  - [How global and project-specific Codex memory works](#how-global-and-project-specific-codex-memory-works)
- [Adding new knowledge files](#adding-new-knowledge-files)

## Purpose

The thing with Claude Code and Codex is that they don't have some basic "common
knowledge", making them do odd things.  Codex doesn't even have a common memory
store for all projects.  This repo is to fill that gap.

## Contents

| File | Purpose |
|------|---------|
| [`CLAUDE.md`](CLAUDE.md) | Global instructions and lessons for Claude Code |
| [`CODEX.md`](CODEX.md) | Global instructions and lessons for Codex |
| [`AGENTS.md`](AGENTS.md) | Project-level bootstrap template for Codex projects |
| [`build_issues.md`](build_issues.md) | Cross-project build and linker mismatch triage playbook |
| [`regex-patterns.md`](regex-patterns.md) | Reusable regex patterns referenced from CLAUDE.md / CODEX.md |
| [`testing.md`](testing.md) | Testing guidelines and discipline referenced from CLAUDE.md |
| [`scripts/normalize-eol.ps1`](scripts/normalize-eol.ps1) | Utility to normalize file EOL style (`CRLF` or `LF`) |
| [`scripts/show-eol.ps1`](scripts/show-eol.ps1) | Utility to report file EOL style (`CRLF`, `LF`, `CR`, `Mixed`, `None`) |
| [`scripts/show-eol.pl`](scripts/show-eol.pl) | Perl utility to report file EOL style (`CRLF`, `LF`, `CR`, `Mixed`, `None`) |
| [`scripts/normalize-eol.pl`](scripts/normalize-eol.pl) | Perl utility to normalize file EOL style (`CRLF` or `LF`) |
| [`.gitignore`](.gitignore) | Deny-all with explicit exceptions for knowledge files |

## Claude Code

Claude Code stores local data at `~/.claude` (on Windows it's at
`$USERPROFILE/.claude`). This can be overridden by specifying the
`$CLAUDE_CONFIG_DIR` environment variable.

### How to Install For Claude Code

This repo is designed to be used from existing tool directories (`~/.claude/` or
`$CLAUDE_CONFIG_DIR`).  When mentioning `~/.claude` directory, this is actually
referencing that or the override.

#### Resolve `CLAUDE_DIR`

POSIX shells (Linux/macOS):

```bash
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

Git Bash on Windows:

```bash
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$(cygpath "$USERPROFILE")/.claude}"
```

#### Existing `CLAUDE_DIR` directory

Since `git clone` refuses to clone into a non-empty directory, initialize git
in place when the directory already exists.

```bash
cd "$CLAUDE_DIR"
git init
git remote add origin https://github.com/Ma-XX-oN/AI-General-Memory.git
git fetch origin
git checkout -b master origin/master
```

#### Fresh machine (no existing `CLAUDE_DIR`)

```bash
git clone https://github.com/Ma-XX-oN/AI-General-Memory.git "$CLAUDE_DIR/"
```

### How global and project-specific Claude Code memory works

1. Keep cross-project lessons in `~/.claude/CLAUDE.md`.
2. Put project-specific rules in `<project>/CLAUDE.md`.

There's no need to copy anything into the project directory to tell Claude Code
to look elsewhere for a central memory store, as it is already done by default.

## Codex

Codex stores local data at `~/.codex` (on Windows it's at
`$USERPROFILE/.codex`). This can be overridden by specifying the `$CODEX_HOME`
environment variable.

### How to Install for Codex

This repo is designed to be used from existing tool directories (`~/.codex/` or
`$CODEX_HOME`).  When mentioning `~/.codex` directory, this is actually
referencing that or the override.

#### Resolve `CODEX_DIR`

POSIX shells (Linux/macOS):

```bash
CODEX_DIR="${CODEX_HOME:-${XDG_CONFIG_HOME:-$HOME/.codex}}"
```

Git Bash on Windows:

```bash
CODEX_DIR="${CODEX_HOME:-$(cygpath "$USERPROFILE")/.codex}"
```

#### Existing `CODEX_DIR` directory

Since `git clone` refuses to clone into a non-empty directory, initialize git
in place when the directory already exists.

```bash
cd "$CODEX_DIR"
git init
git remote add origin https://github.com/Ma-XX-oN/AI-General-Memory.git
git fetch origin
git checkout -b master origin/master
```

#### Fresh machine (no existing `CODEX_DIR`)

```bash
git clone https://github.com/Ma-XX-oN/AI-General-Memory.git "$CODEX_DIR/"
```

### How global and project-specific Codex memory works

1. Copy this repo's `AGENTS.md` into each project root.
2. Keep cross-project lessons in `~/.codex/CODEX.md`.
3. Put project-specific rules in `<project>/CODEX.md`.

## Adding new knowledge files

1. Create the file in the repo.
2. Add a `!filename` entry to `.gitignore`.
3. Reference the file from `CLAUDE.md`, `CODEX.md`, or both.
4. Stage, commit, and push.
