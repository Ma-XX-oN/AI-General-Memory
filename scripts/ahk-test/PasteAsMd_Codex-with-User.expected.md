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
**Codex:**
>
> # Heading Level 1
>
> ## Heading Level 2
>
> ### Heading Level 3
>
> This paragraph uses **bold**, *italic*, ***bold-italic***, ~~strikethrough~~, `inline code`, and [a link](https://example.com/).
>
>     def greet(name):
>         message = f"Hello, {name}!"
>
>         return message
>
>     print(greet("world"))
>
>     function greet(name) {
>       const message = `Hello, ${name}!`;
>
>       return message;
>     }
>
>     console.log(greet("world"));
>
>     echo "Starting job"
>     mkdir -p ./tmp
>     echo "Done"
>
> - [x] Checked item
> - [ ] Unchecked item
>
> > This is the outer blockquote.
> >
> > > This is the nested blockquote.  
> > > It has a second line.
> >
> > Back to the outer blockquote.
>
> | Left | Center | Right |
> |------|--------|-------|
> | L1   | C1     | R1    |
> | L2   | C2     | R22   |
>
> - Unordered item one
> - Unordered item two
>   - Nested unordered item
> - Unordered item three
>
> 1.  Ordered item one
> 2.  Ordered item two
> 3.  Ordered item three with footnote reference<sup>[1](#user-content-fn-note)</sup>
>
> ## Footnotes
>
> 1.  This is the footnote definition. [↩︎](#user-content-fnref-note)
