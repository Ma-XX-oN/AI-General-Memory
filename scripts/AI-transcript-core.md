# AI-transcript.py — AIConversationCore Integration

`AI-transcript.py` keeps its Python-owned CLI, session discovery, JSONL I/O,
record/time filtering, grep/search, session selection, and output routing.  ChatGPT,
Claude, and Codex transcript presentation is rendered by `AIConversationCore`
through one persistent Node.js worker (`AI-transcript-core-worker.mjs`).

## Requirements

- Node.js must be available as `node`, or through the executable named by the
  `NODE` environment variable.
- `AIConversationCore` is tracked as the Git submodule at
  `dependencies/AIConversationCore` and must be initialized.
- `AI_CONVERSATION_CORE` may override the submodule path for development/CI,
  but it must name an AIConversationCore repository root, not a JavaScript file.
- The checkout must be exactly commit
  `f34f0dc931d03862e88ca185cdddf8c964a25325`.  The worker verifies the checkout
  HEAD before importing the core and refuses to run against a different revision.
- Run `./pull-AI-General-Memory.sh` to fast-forward AI-General-Memory and
  initialize/synchronize the pinned submodule.

## Bridge behaviour

The Python process starts one line-delimited JSON Node.js worker and reuses it for
the process lifetime.  It does not spawn a JavaScript process per source record.
Python reads/filter-selects the source JSONL records and supplies consumer-specific
projection metadata such as date, record number, optional source turn ID,
ANSI presentation, separate-thought mode, and debug provenance enablement.  Provider interpretation,
canonical structures, and Markdown rendering remain in `AIConversationCore`.

## Optional source turn IDs

`--turn-id` is a normal transcript presentation option, independent of `-d`,
`-n`, and `-N`.  ChatGPT headings use the source message `id`; Claude
headings use the source record `uuid`.  Codex does not expose a suitable
UUID-like ID for every rendered record, so requesting `--turn-id` for Codex
emits one warning and no `turn_id` fields.

## Debug provenance

`-N` remains the transcript debugging switch.  Its former
`<!-- record: N -->` output is superseded.  With `-N`, renderer-generated
headings/groupings use canonical source provenance:

```markdown
## ChatGPT <!-- turn_id=<source_record_id> record_index=<zero-based-index> -->
```

The same rule applies to User/provider/sub-agent/question/plan/thought/tool and
other renderer-generated structural headings/groupings.  When one rendered group
represents multiple source records, the first source is attached to the opening
line and later source records are emitted on immediately following HTML-comment
lines.

## Verification

Permanent CI checks out the pinned AIConversationCore submodule, verifies that
its HEAD matches the superproject gitlink and the worker-reported core commit,
compares the production Python entry point against the historical pre-Phase-6
implementation except for explicitly recorded canonical decisions, compares
ChatGPT/Claude/Codex output with canonical goldens, runs the portable fixture-based
`AI-transcript.py` regression subset, runs the core test suite, and checks diff
hygiene.

## Codex supplementary source ownership

For Codex, the Python caller discovers the optional `session_index.jsonl` path and passes that path to AIConversationCore. The caller does not parse or interpret the index. AIConversationCore owns reading JSONL, matching the rollout/session UUID, choosing the last valid matching title, rollback/edit semantics, model-change semantics, and revision filtering. Rolled-back history remains hidden by default; `--include-rolled-back` passes `includeRolledBackTurns=true` to the core. Recorded Codex IDE context is preserved verbatim.
