# Regex Patterns

## Generalized bracketed-text matching

A generic PCRE pattern for matching text delimited by a repeated character
(e.g. backticks for markdown code spans, or any similar bracket style where
the opening/closing delimiter is N repetitions of the same character).

### Pattern (PCRE)

```regex
(?<open>CHAR++)(?:[^CHAR]++|(?!\k<open>).)++\k<open>
```

### How it works

| Part                    | Purpose                                                   |
|-------------------------|-----------------------------------------------------------|
| `(?<open>CHAR++)`       | Capture the opening delimiter (1+ of CHAR, possessive)    |
| `[^CHAR]++`             | Match non-delimiter characters (possessive)               |
| `(?!\k<open>).`         | Match a single CHAR only if it doesn't start a closing    |
|                         | delimiter sequence equal to the opening                   |
| `\k<open>`              | Closing delimiter must exactly match the opening           |

The `++` possessive quantifiers prevent catastrophic backtracking.

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
- Works as a PCRE subroutine when wrapped in a named group and placed
  in a dead-alternation library (`|(?!)...`).
