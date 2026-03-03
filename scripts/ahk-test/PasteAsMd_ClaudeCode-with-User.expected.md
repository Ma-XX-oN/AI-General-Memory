**User:**
>
> Output a markdown test document demonstrating each of the following. No explanations — just the document.
>
> Required sections, in order:
>
> 1.  Three heading levels (H1, H2, H3)
> 2.  An inline-formatting paragraph using bold, italic, bold-italic, strikethrough, inline code, and a link
> 3.  Three fenced code blocks with language tags: one Python (with at least one blank line inside), one JavaScript (with at least one blank line inside), one Bash
> 4.  A task list with at least one checked and one unchecked item
> 5.  A blockquote with a nested blockquote inside
> 6.  A table with left, center, and right column alignment
> 7.  An unordered list with at least one nested item
> 8.  An ordered list
> 9.  A footnote reference and its definition
>
**Claude Code:**
>
> The user wants a markdown test document. No explanations, just the document.
>
> # Heading One
>
> ## Heading Two
>
> ### Heading Three
>
> This paragraph uses **bold**, *italic*, ***bold-italic***, ~~strikethrough~~, `inline code`, and a [link](https://example.com/).
>
> ```python
> def greet(name):
>     greeting = f"Hello, {name}!"
>
>     return greeting
> ```
>
> ```javascript
> function greet(name) {
>   const greeting = `Hello, ${name}!`;
>
>   return greeting;
> }
> ```
>
> ```bash
> echo "Hello, world!"
> ```
>
> - [x] Checked item
> - [ ] Unchecked item
> - [x] Another checked item
>
> > Outer blockquote line.
> >
> > > Nested blockquote line.
>
> | Left | Center | Right |
> |:-----|:------:|------:|
> | a    |   b    |     c |
> | foo  |  bar   |   baz |
>
> - Item one
>   - Nested item
>   - Another nested item
> - Item two
> - Item three
>
> 1.  First
> 2.  Second
> 3.  Third
>
> Here is a footnote reference.<sup>[1](#user-content-fn-1)</sup>
>
> ## Footnotes
>
> 1.  This is the footnote definition. [↩︎](#user-content-fnref-1)
