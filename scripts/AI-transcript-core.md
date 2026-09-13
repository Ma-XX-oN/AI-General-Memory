# AI-transcript.py — AIConversationCore Integration

`AI-transcript.py` keeps its Python-owned CLI, session discovery, JSONL I/O,
record/time filtering, grep/search, session selection, and output routing.  ChatGPT,
Claude, and Codex transcript presentation is rendered by `AIConversationCore`
through one persistent Node.js worker (`AI-transcript-core-worker.mjs`).

## Requirements

- Node.js must be available as `node`, or through the executable named by the
  `NODE` environment variable.
- An `AIConversationCore` checkout must be available either as a sibling of this
  repository or at the repository path named by `AI_CONVERSATION_CORE`.
- `AI_CONVERSATION_CORE` must name the repository root, not a JavaScript file.
- The checkout must be exactly commit
  `d6d76b54db3d48baf3f5e3a76099be1732d32785`.  The worker verifies the checkout
  HEAD before importing the core and refuses to run against a different revision.

## Bridge behaviour

The Python process starts one line-delimited JSON Node.js worker and reuses it for
the process lifetime.  It does not spawn a JavaScript process per source record.
Python reads/filter-selects the source JSONL records and supplies only presentation
policy: heading visibility, timezone choice, ANSI styling, and separate-thought mode.
Timestamp, record number, source turn ID, and debug provenance values are derived and
serialized by `AIConversationCore` from canonical source provenance.  Provider
interpretation, canonical structures, and Markdown rendering remain in Core.

## Optional source turn IDs

`--turn-id` is a normal transcript presentation option, independent of `-d`,
`-n`, and `-N`.  ChatGPT headings use the source message `id`; Claude
headings use the source record `uuid`.  The visible heading component is the bare
native ID value; Core does not prefix it with `turn_id=`.  Codex does not expose a
suitable UUID-like ID for every rendered record, so requesting `--turn-id` for
Codex emits one warning and no Turn ID component.

## Debug provenance

`-N` remains the transcript debugging switch.  Its former
`<!-- record: N -->` output is superseded.  With `-N`, renderer-generated
headings/groupings use canonical source provenance:

```markdown
## ChatGPT <!-- record_id=<native-source-record-id> record_index=<zero-based-index> -->
```

When `--turn-id` and `-N` are both requested, the bare visible Turn ID heading
component and the debug provenance comment are emitted independently.  The same
provenance rule applies to User/provider/sub-agent/question/plan/thought/tool and
other renderer-generated structural headings/groupings.  Related-source structures
use their own Core-derived source metadata.

## Verification

Permanent CI compares the production Python entry point against the historical
pre-Phase-6 implementation except for explicitly recorded canonical decisions,
compares ChatGPT/Claude/Codex output with canonical goldens, runs the portable
fixture-based `AI-transcript.py` regression subset, runs the core test suite, and
checks diff hygiene.
