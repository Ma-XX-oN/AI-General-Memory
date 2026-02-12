# AGENTS.md

## Codex bootstrap

At the start of each task:

1. Read global memory from `$CODEX_HOME/CODEX.md`.
2. If `<project>/CODEX.md` exists, read it after `$CODEX_HOME/CODEX.md`.
3. Apply precedence in this order (highest first):
   `<project>/AGENTS.md` > `<project>/CODEX.md` > `$CODEX_HOME/CODEX.md`.
4. Before running build/test/tool commands, list applicable execution rules from loaded `CODEX.md` files and apply them directly in the command (for example required `PATH` prefixes).

## Memory placement

- Cross-project lessons go in `$CODEX_HOME/CODEX.md`.
- Project-specific lessons go in `<project>/CODEX.md`.
