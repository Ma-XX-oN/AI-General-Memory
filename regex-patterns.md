# Regex Patterns

## Debugging

Test quantifier behavior (`*`, `+`, `?`) on the first concrete
match/counterexample before considering line-ending or engine-specific
explanations.

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

### PCRE inline comments `(?#...)`

PCRE inline comments are terminated by the **first** `)` encountered —
there is no escape mechanism inside `(?#...)`.  Any `)` in the comment
body (e.g. from an embedded pattern like `(?<tag>...)`) closes the
comment prematurely, leaving the rest as unmatched pattern text and
causing a compile error.

**Safe:** keep comment text free of `)`:

```regex
(?<void_tag> (?# void element fallback — entered when first alt fails )
```

**Broken:** `)` inside the comment body terminates it early:

```regex
(?<void_tag> (?# entered when the first alt of (?<tag>...) fails )
```

With the `x` (extended) flag, `#`-style end-of-line comments are also
available and have no such restriction.

### PCRE `J` flag and duplicate named groups in recursive subroutines

The `J` flag allows two groups to share a name (e.g. `(?<tag_name>...)` in
both alternatives of a `(?(DEFINE)...)` subroutine).  **Avoid this in
recursive patterns.** Two problems arise:

1. **`m["name"]` in callouts always returns the first group** (by source
   order), even when the second group is the one that just captured.  The
   first group carries the outer call's value, which leaks into inner
   callouts.

2. **`\k<name>` picks up the most recently captured value** across both
   groups, including values from nested subroutine calls, corrupting
   backreferences in the outer context.

**Fix:** give each subroutine its own uniquely-named capture group.
For a void-element fallback in a recursive HTML tag parser, extract the
fallback into a separate `(?<void_tag>...)` subroutine that captures into
`(?<void_name>...)` instead of reusing `(?<tag_name>...)`.  The callout
then checks `m["void_name"] != "" ? m["void_name"] : m["tag_name"]`.
No `J` flag needed.

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

## AHK PCRE callout debugger

Visualises the engine's position in both the haystack and the needle at each
callout point.  Paste the body into an existing callout function, or define
it as a standalone top-level function and invoke it with `(?C:debug)`.

### Callout syntax

- `(?C:name)` — named callout (AHK extension; preferred over `(?Cname)` to
  reduce spellcheck warnings).
- `C)` flag — **auto-callout**: PCRE inserts callout 255 before every item
  in the pattern automatically, invoking the `pcre_callout` global.  Very
  informative for small patterns; generates a lot of output for large ones
  but has still proven useful for tracing complex match behaviour.

### Debugger function

```ahk
debug(Match, CalloutNumber, FoundPos, Haystack, NeedleRegEx) {
  ; See pcre.txt for descriptions of these fields.
  start_match       := NumGet(A_EventInfo, 12 + A_PtrSize*2, "Int")
  current_position  := NumGet(A_EventInfo, 16 + A_PtrSize*2, "Int")
  pad := A_PtrSize=8 ? 4 : 0
  pattern_position  := NumGet(A_EventInfo, 28 + pad + A_PtrSize*3, "Int")
  next_item_length  := NumGet(A_EventInfo, 32 + pad + A_PtrSize*3, "Int")

  ; Point out >>current match<<.
  _HAYSTACK := SubStr(Haystack, 1, start_match)
    . "🠞" SubStr(Haystack, start_match + 1, current_position - start_match)
    . "🠜" SubStr(Haystack, current_position + 1)

  ; Point out >>next item to be evaluated<<.
  _NEEDLE := SubStr(NeedleRegEx, 1, pattern_position)
    . "🠞" SubStr(NeedleRegEx, pattern_position + 1, next_item_length)
    . "🠜" SubStr(NeedleRegEx, pattern_position + 1 + next_item_length)

  FileAppend "Haystack:`n" _HAYSTACK "`nNeedle:`n" _NEEDLE "`n", "**"
}
```

The arrows `🠞…🠜` bracket the active region.  In the haystack they surround the
portion already consumed by the current match attempt (`start_match` to
`current_position`).  In the needle they surround the next item about to be
evaluated (`pattern_position` + `next_item_length`).

`A_EventInfo` points to a PCRE2 `pcre2_callout_block_8` struct; offsets
are documented in the PCRE2 source (`pcre2.h`) and in `pcre2_callout(3)`.

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
