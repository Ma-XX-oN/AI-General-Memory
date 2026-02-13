# Regex Patterns

## General techniques

### Possessive quantifiers and atomic groups

Use possessive quantifiers (`++`) or atomic groups (`(?>...)`) to
prevent catastrophic backtracking wherever the engine doesn't need to
revisit a subexpression.  Always prefer them unless the flavour doesn't
support them or backtracking is intentionally needed for the match.

- **Possessive quantifiers** (`++`): supported by PCRE, Java,
  Oniguruma, and others.
- **Atomic groups** (`(?>...)`): equivalent mechanism, available in
  .NET and other flavours that lack possessive quantifiers.
- **Neither available** (e.g. JavaScript): restructure alternatives to
  match exactly one character per iteration so that there is only one
  possible decomposition, eliminating exponential backtracking.  The
  engine can still backtrack (e.g. into a greedy quantifier on an
  earlier group), so be aware of semantic differences.

### Lazy quantifiers

Lazy (reluctant) quantifiers (`+?`, `*?`) match as little as possible,
extending only when the rest of the pattern fails.  They control match
*semantics* (shortest vs longest match), not backtracking *safety* —
the engine still explores alternatives and can degrade on adversarial
input.  Use lazy quantifiers when you want to stop at the first
occurrence of an unambiguous, fixed terminator (e.g. `.*?-->` for HTML
comments).  Do not use them as a substitute for possessive/atomic when
the goal is to prevent catastrophic backtracking.

### Subroutines and inlining

Subroutines (e.g. PCRE `(?&name)`, Oniguruma `\g<name>`) allow a
named subpattern to be reused and called recursively.  In flavours
without subroutines:

- The pattern can be inlined at each call site.
- For recursive matching (e.g. balanced parentheses), the pattern must
  be manually nested to a fixed depth — each level requires another
  copy of the pattern embedded inside itself.  This works but is
  harder to maintain and limits matching to the chosen nesting depth.
- It can be easier to design and reason about the pattern using
  subroutines first, then mechanically inline them for the target
  flavour.

## Generalized bracketed-text matching

A generic pattern for matching text delimited by a repeated character
(e.g. backticks for markdown code spans, or any similar bracket style where
the opening/closing delimiter is N repetitions of the same character).

Requires named backreferences (`\k<name>`).

### Pattern (possessive)

```regex
(?<open>CHAR++)(?:[^CHAR]++|(?!\k<open>).)++\k<open>
```

Best form.  Requires possessive quantifiers (`++`).

### Pattern (atomic groups)

```regex
(?>(?<open>CHAR+))(?:(?>[^CHAR]+)|(?!\k<open>).)+\k<open>
```

Equivalent to the possessive form.  Use in flavours that support
atomic groups but not possessive quantifiers.

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
| `\k<open>`              | Closing delimiter must exactly match the opening          |

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
- Can be used as a subroutine when wrapped in a named group and placed
  in a dead-alternation library (`|(?!)...`).
