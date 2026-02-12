# Regex Patterns

## Generalized bracketed-text matching

A generic pattern for matching text delimited by a repeated character
(e.g. backticks for markdown code spans, or any similar bracket style where
the opening/closing delimiter is N repetitions of the same character).

Requires a regex flavour that supports named backreferences
(`\k<name>`).  Possessive quantifiers (`++`) or atomic groups
(`(?>...)`) are strongly recommended — always use them unless the
flavour doesn't support them or backtracking into the delimiter is
intentionally desired.

### Pattern (possessive)

```regex
(?<open>CHAR++)(?:[^CHAR]++|(?!\k<open>).)++\k<open>
```

Best form.  Requires possessive quantifiers (`++`), supported by
PCRE, Java, Oniguruma, and others.

### Pattern (atomic groups)

```regex
(?>(?<open>CHAR+))(?:(?>[^CHAR]+)|(?!\k<open>).)+\k<open>
```

Equivalent to the possessive form.  Use in flavours that support
atomic groups but not possessive quantifiers (e.g. .NET).

### Pattern (no possessive / no atomic)

```regex
(?<open>CHAR+)(?:[^CHAR]|(?!\k<open>).)+\k<open>
```

Fallback for flavours without possessive quantifiers or atomic groups
(e.g. JavaScript with named groups).  Still linear-time because each
alternative in the content loop matches exactly one character,
eliminating ambiguous decompositions.

**Caveat:** Without possessive/atomic on the opening `CHAR+`, the
engine can backtrack into the opener and shrink it.  For example,
against `cccabcc` (where `c` is CHAR), the possessive form matches
with `open` = `cc` and content = `ab`, while this form matches with
`open` = `cc` and content = `cab` — the opener greedily captures
`ccc`, fails to find a 3-character closing delimiter, backtracks to
`cc`, and the released `c` is absorbed into the content.  This may or
may not matter depending on the use case.

### How it works

| Part                    | Purpose                                                   |
|-------------------------|-----------------------------------------------------------|
| `(?<open>CHAR++)`       | Capture the opening delimiter (1+ of CHAR, possessive)    |
| `[^CHAR]++`             | Match non-delimiter characters (possessive)               |
| `(?!\k<open>).`         | Match a single CHAR only if it doesn't start a closing    |
|                         | delimiter sequence equal to the opening                   |
| `\k<open>`              | Closing delimiter must exactly match the opening           |

The `++` possessive quantifiers prevent catastrophic backtracking.
In the non-possessive fallback, single-character alternatives achieve
the same linear-time guarantee, but do not prevent backtracking into
the opening delimiter.

### Example: markdown code spans

Replace `CHAR` with a literal backtick:

```regex
(?<bt_open>`++)(?:[^`]++|(?!\k<bt_open>).)++\k<bt_open>
```

This matches `` `code` ``, ``` ``code with `backtick` inside`` ```,
```` ```code with ``two`` backticks``` ````, etc.  The opening delimiter
length is captured and the closing must match exactly.

### Notes

- Content group uses `++` (one or more), so empty delimited spans like
  `` ` ` `` won't match.  This is fine when protecting content from
  destructive transforms — empty spans have nothing to protect.
- Works as a subroutine (in flavours that support them, e.g. PCRE)
  when wrapped in a named group and placed in a dead-alternation
  library (`|(?!)...`).
- In flavours without subroutines, the pattern can be inlined at each
  call site.  For recursive matching (e.g. balanced parentheses), the
  pattern must be manually nested to a fixed depth — each level
  requires another copy of the pattern embedded inside itself.  This
  works but is harder to maintain and limits matching to the chosen
  nesting depth.  It can be easier to design and reason about the
  pattern using subroutines first, then mechanically inline them for
  the target flavour.
