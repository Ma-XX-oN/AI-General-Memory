# AGENTS.md

## Codex bootstrap

At the start of each task:

1. Read global memory from `$CODEX_HOME/CODEX.md`.
2. If `<project>/CODEX.md` exists, read it after `$CODEX_HOME/CODEX.md`.
3. Apply precedence in this order (highest first):
   `<project>/AGENTS.md` > `<project>/CODEX.md` > `$CODEX_HOME/CODEX.md`.

## Memory placement

- Cross-project lessons go in `$CODEX_HOME/CODEX.md`.
- Project-specific lessons go in `<project>/CODEX.md`.
