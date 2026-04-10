# AI General Memory <!-- omit in toc -->

![Social Preview](social-preview.svg)

Author: _Adrian Hawryluk_ (a.k.a. [Ma-XX-oN](https://github.com/Ma-XX-oN))

Shared knowledge files for Claude Code and Codex.

- [Purpose](#purpose)
- [Contents](#contents)
  - [AI Data](#ai-data)
  - [Scripts](#scripts)
  - [User Files](#user-files)
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

I use both Claude Code and Codex collaboratively to get things done.  However,
the thing with these AIs is that they don't have some basic "common knowledge",
making them do odd things.  Codex doesn't even have a common memory store for
all projects.  This repo is to fill that gap.

> **NOTE:**
>
> This will only mitigate most of the odd behaviour, not completely stop it.

Scripts are mainly for Codex as it tends to do more irritating things. Such as
making allow popups pop up all the time and foobaring files line endings
resulting in mixed EOLs.  However, it seems that Claude has found the line
ending tools somewhat useful as well, though mostly for confirmation purposes.

## Contents

Most of these files are used by the AIs. A few are used directly by the user.

### AI Data

| File | User | Purpose |
| --- | --- | --- |
| [`CLAUDE.md`](CLAUDE.md) | Claude | Global instructions and lessons for Claude Code |
| [`CODEX.md`](CODEX.md) | Codex | Global instructions and lessons for Codex |
| [`AGENTS.md`](AGENTS.md) | Codex | Project-level bootstrap template for Codex projects |
| [`ahk.md`](ahk.md) | AIs | AutoHotkey v2 patterns and pitfalls (Git Bash, strings, concat) |
| [`build_issues.md`](build_issues.md) | AIs | Build and linker mismatch triage playbook |
| [`regex-patterns.md`](regex-patterns.md) | AIs | Reusable regex patterns |
| [`testing.md`](testing.md) | AIs | Testing guidelines and discipline |
| [`workflow.md`](workflow.md) | AIs | TTD/testing/command-workflow guidance to reduce approval friction |

### Scripts

| File | User | Purpose |
| --- | --- | --- |
| [`scripts/session-pid.sh`](scripts/session-pid.sh) | AIs | Print the stable AI agent session PID (bash entry point — must be sourced) |
| [`scripts/session-pid.ps1`](scripts/session-pid.ps1) | AIs | Print the stable AI agent session PID (PowerShell implementation, called by `session-pid.sh` and usable directly from Codex) |
| [`scripts/normalize-eol.ps1`](scripts/normalize-eol.ps1) | All | Normalize file EOL style (`CRLF` or `LF`) — PowerShell |
| [`scripts/normalize-eol.pl`](scripts/normalize-eol.pl) | All | Normalize file EOL style (`CRLF` or `LF`) — Perl |
| [`scripts/show-eol.ps1`](scripts/show-eol.ps1) | All | Report file EOL style (`CRLF`, `LF`, `CR`, `Mixed`, `None`) — PowerShell |
| [`scripts/show-eol.pl`](scripts/show-eol.pl) | All | Report file EOL style (`CRLF`, `LF`, `CR`, `Mixed`, `None`) — Perl |
| [`scripts/PasteAsMd.ahk`](scripts/PasteAsMd.ahk) | User | User-to-AI communication via markdown-safe paste.<ul><li>Requires [AutoHotkey](https://www.autohotkey.com/) and [pandoc](https://pandoc.org/).</li><li>Maps `Ctrl-Alt-Shift-v` to a menu to paste as Markdown or quoted Markdown.</li></ul> |
| [`scripts/CopyClip.ahk`](scripts/CopyClip.ahk) | User | Display what clipboard types were copied with keyboard shortcuts.<ul><li>Requires [AutoHotkey](https://www.autohotkey.com()).</li><li>Tracks `Ctrl-c`, `Ctrl-Ins`, `Ctrl-PrtSc` and `Alt-PrtSc`.</li><li>Useful to confirm copy since clipboard fill can lag.</li></ul> |
| [`scripts/AI-transcript.py`](scripts/AI-transcript.py) | All | Unified transcript and session search for both Claude and Codex.<ul><li>Usage: `python scripts/AI-transcript.py [--claude\|--codex\|--both-AIs] [--ls\|--id GLOB_OR_UUID\|--grep TEXT\|--grep-re PATTERN] [output.md]`</li><li>Lists sessions, generates Markdown transcripts, and greps session content across both AIs.</li><li>Supports `--all-projects`, context lines `-A/-B/-C/-x`, `--words-only`, and `--color`.</li></ul> |
| [`scripts/AI-transcript-arch.md`](scripts/AI-transcript-arch.md) | All | Architecture reference for `AI-transcript.py`: JSONL schema, transcript pipeline, hunk data structure, grep pipeline threading pattern. |
| [`scripts/cont-claude-prompt.bat`](scripts/cont-claude-prompt.bat) | User | Resume a Claude Code session with a `continue` prompt immediately or deferred to a future date/time via Windows Task Scheduler.  Usage: `cont-claude-prompt.bat [-t hh:mm] [-d date] [--wd dir] [-D] UUID` |
| [`scripts/prettify-jsonl.py`](scripts/prettify-jsonl.py) | User | Pretty-print selected records from a JSONL file (e.g. Claude/Codex session files).  Usage: `python scripts/prettify-jsonl.py [-s START] [-e END] [file]` |
| [`scripts/fixtures/`](scripts/fixtures/) | All | Minimal JSONL fixture files for `AI-transcript.py` regression tests (used with `--file`).  See `AI-transcript-arch.md` for descriptions. |

### User Files

| File | User | Purpose |
| --- | --- | --- |
| [`USER.md`](USER.md) | User | Effective techniques for using AI |
| [`social-preview.svg`](social-preview.svg) | User | Repository social preview artwork |
| [`LICENSE`](LICENSE) | User | Apache License 2.0 terms for repository content |
| [`NOTICE`](NOTICE) | User | Project and contributor attribution notice file |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | User | Contribution workflow and expectations |
| [`AUTHORS.md`](AUTHORS.md) | User | Maintainer and contributor attribution list |
| [`.gitignore`](.gitignore) | User | Deny-all with explicit exceptions for tracked files |

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
