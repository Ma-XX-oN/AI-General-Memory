**User:**
>
> Output a markdown test document demonstrating each of the following. No explanations — just the document.
> Required sections, in order:
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
> 11:25
>
**Claude Web:**
>
> # Markdown Test Document
>
> ## Section 1
>
> ### Headings
>
> Here is a paragraph with **bold**, *italic*, ***bold-italic***, ~~strikethrough~~, `inline code`, and a [link](https://www.example.com).
>
> ## Section 2
>
> ```python
> def hello_world():
>     print("Hello, World!")
>
> hello_world()
> ```
>
> ```javascript
> function greet(name) {
>     console.log(`Hello, ${name}!`);
> }
>
> greet("JavaScript");
> ```
>
> ```bash
> echo "Hello from Bash!"
> ```
>
> ## Section 3
>
> - [x] Complete task 1
> - [ ] Incomplete task 2
> - [x] Complete task 3
>
> ## Section 4
>
> > This is a blockquote.
> >
> > > This is a nested blockquote.
>
> ## Section 5
>
> | Left-aligned | Center-aligned | Right-aligned |
> |:-------------|:--------------:|--------------:|
> | Apple        |     Banana     |        Cherry |
> | Durian       |   Elderberry   |           Fig |
>
> ## Section 6
>
> - Fruits
>   - Apple
>   - Banana
> - Vegetables
> - Grains
>
> ## Section 7
>
> 1.  First item
> 2.  Second item
> 3.  Third item
>
> ## Section 8
>
> This is a sentence with a footnote reference.<sup>[1](#user-content-fn-1)</sup>
>
> ## Footnotes
>
> 1.  This is the footnote definition. [↩︎](#user-content-fnref-1)
