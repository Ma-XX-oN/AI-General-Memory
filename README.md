# Claude Code Global Knowledge

Shared knowledge files for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).
Claude Code automatically loads `~/.claude/CLAUDE.md` into every project,
making it the ideal place for cross-project lessons, conventions, and patterns.

## Contents

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Global instructions and lessons (auto-loaded by Claude Code) |
| `regex-patterns.md` | Reusable regex patterns referenced from CLAUDE.md |
| `.gitignore` | Deny-all with explicit exceptions for knowledge files |

## Installation

Claude Code creates `~/.claude/` on first run and populates it with config
files.  Since `git clone` refuses to clone into a non-empty directory, the
recommended approach is to initialise git in the existing directory:

```bash
cd ~/.claude
git init
git remote add origin <repo-url>
git fetch origin
git checkout -b master origin/master
```

On Windows, replace `~/.claude` with `%USERPROFILE%\.claude` (cmd) or
`$env:USERPROFILE\.claude` (PowerShell).

The `.gitignore` uses a deny-all `*` rule with explicit `!filename` exceptions,
so only knowledge files are tracked — Claude Code's own config files are
ignored.

### Fresh machine (no existing ~/.claude/)

If `~/.claude/` doesn't exist yet, a direct clone works:

```bash
git clone <repo-url> ~/.claude/
```

## Adding new knowledge files

1. Create the file in `~/.claude/`.
2. Add a `!filename` entry to `.gitignore` (it uses a deny-all `*` rule).
3. Reference the file from `CLAUDE.md` if appropriate.
4. Stage, commit, and push.

## How it works

Claude Code loads files in this order for every conversation:

1. `~/.claude/CLAUDE.md` (global — this repo)
2. `<project>/CLAUDE.md` (project-specific)
3. `<project>/CLAUDE.local.md` (personal, gitignored)
4. `<project>/.claude/rules/*.md` (modular project rules)

General knowledge belongs here. Project-specific knowledge stays in the
project's own `CLAUDE.md`.
