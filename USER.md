# How to Effectively Use AI for Coding <!-- omit in toc -->

- [Purpose](#purpose)
- [Generate a Plan](#generate-a-plan)
- [Break Down the Plan into Smaller Chunks](#break-down-the-plan-into-smaller-chunks)
- [For Complex Items, Make the Plan a Living Document](#for-complex-items-make-the-plan-a-living-document)
- [Try and Avoid Scope Creep](#try-and-avoid-scope-creep)
- [Read What the AI is Thinking](#read-what-the-ai-is-thinking)
- [`git` is Your Friend](#git-is-your-friend)
- [TDD is Your Friend](#tdd-is-your-friend)
- [Logging and Replay](#logging-and-replay)
- [Self Reflection](#self-reflection)
- [Use Multiple Models](#use-multiple-models)
  - [What Claude Code Thinks](#what-claude-code-thinks)
  - [What Codex Thinks](#what-codex-thinks)
  - [What I Think](#what-i-think)

## Purpose

There's no doubt that AI is amazing at helping you write stuff. However, if you
want to build something maintainable, you shouldn't just tell it to do
whatever it wants. You need to give it some guidance. This repo helps with
that, but it isn't just the AI that needs guidance. You, the user, also need
guidance on how to use the AI. That's what this file is for.

## Generate a Plan

When you have a plan, you know when things are done. Figure out what you want
and get the AI to understand what that is. Use the AI to help you with this.
It's a great sounding board for figuring out what you actually want.

## Break Down the Plan into Smaller Chunks

When you have a big plan, you need to break it down into smaller, more
manageable pieces. This helps you visualise the entire system. It also helps
you see progress when the individual pieces are done. This is not just for
writing with AI; it's a general philosophy for getting things done.

## For Complex Items, Make the Plan a Living Document

This is your design document. It should list what you're trying to accomplish,
possible design specs, maybe some UML to help visualise it, and a list of
subtasks to get it done. The AI should be allowed to update the task list as
items are completed.

This document should describe the MVP (minimum viable product).

## Try and Avoid Scope Creep

If you find that your scope is widening, stop. Add a section to your design
document that lists things that could or should be added later. This helps keep
you from forgetting ideas you've had.

Stick with your MVP. Once the MVP is complete, you can go back and add those
features later. It's also a good idea to track bugs in a similar way. These
are just more task lists for you and the AI to work through later.

## Read What the AI is Thinking

The AI thinks a lot. That thinking can be useful. It can show you when it is
going off the rails, looping, doing something that is not a good idea, or
heading somewhere you did not intend. Reading this output can help you get
ahead of problems by giving it missing information before it fills in the gaps
on its own. You don't have to read the entire thing; just skim it.

You can actually steer Codex by typing in a prompt and pressing Ctrl-Enter.
Pressing Enter just queues it to be delivered at the end of the current prompt.
If you accidentally put it in the queue, either press Ctrl-Enter or press the
`steer` button. In Claude, you just type a prompt and hit Enter. There is no
queueing in Claude. Both get your prompt as soon as they're able to, usually
when they stop thinking about one thing and use a tool to do something. If you
ask a question related to what it's doing, this repo is set up so that it
stops until you're satisfied. However, if you just state something, it'll
incorporate it into what it's already doing.

If you find that it's looping or stuck and using a lot of tokens, just hit the
stop button and write a prompt to clarify the issue or ask what it's doing. I
think stopping it does cause the AI to lose a little of what it was doing while
thinking, but it can save you from running out of tokens due to a logic loop.

## `git` is Your Friend

You should always get your AI to commit once it's finished with a task. This is
standard behaviour for any developer, but for AI it's crucial because if it
does something bad, the entire run is not necessarily compromised, especially
when it was told to do several tasks at once.

It's also a good idea when you're about to do something risky (AI or not) so
that you can see what you changed and potentially roll back.

## TDD is Your Friend

Test Driven Development has always been a good idea, but even more so with AI
writing code. That's because AI needs a target and needs to know when it has
reached that target and when it hasn't. You don't have to write the tests
yourself; you can get the AI to write them from the requirements. You can then
review those tests to see whether they cover everything you need. That way you
can go for a coffee and come back and hopefully things are done, assuming it
hasn't stopped to ask you a question or a security prompt hasn't popped up.

## Logging and Replay

For complicated tasks, it can be useful to create logs that show what is coming
in and what is going out of whatever object you're testing. These logs can be
critical for writing robust tests because you can retrofit them to replay the
situation and see whether the output is what was intended. This is also good
for verifying that changes have not compromised the invariants you rely on.

## Self Reflection

I've written a script called AI-transcript.py that will allow you to see the
conversation between you and the AI. You can actually use this to help the AI
reflect on what it has done and possibly give it something to write down in its
memory (either global or project memory) so that it doesn't do it again
(mostly).

## Use Multiple Models

You can just use one model, but why restrict yourself.  One is good, but each
have their own positives and negatives.

----

Claude, what advantages/disadvantages do you think you have over Codex?

### What Claude Code Thinks

> **Advantages**
>
> - *Reasoning depth.* Extended thinking lets me work through complex problems —
>   architectural decisions, multi-file debugging, ambiguous requirements — more
>   thoroughly than a straight completion pass.
> - *Mixed code-and-prose tasks.* Documentation, commit messages, code review
>   write-ups, design docs. These play to my strengths.
> - *Dialogue.* I can ask clarifying questions mid-task, push back on
>   requirements that seem wrong, and stop when something doesn't feel right
>   rather than filling in the gaps silently.
> - *Long-context coherence.* I maintain a consistent understanding across large
>   codebases and long conversations better than models optimised purely for
>   completion.
>
> **Disadvantages**
>
> - *No inline IDE integration.* I work through a CLI. I can't autocomplete
>   inside a file the way Codex does natively in VS Code. *(**Author's note:** This
>   is actually wrong according to Codex)*
> - *Verbosity.* I over-explain. For a quick one-liner fix, Codex is faster and
>   less noisy.
> - *Prose cleanup.* As demonstrated in this very session: I flagged typos but
>   missed grammar errors and style problems. Codex's prose pass was better.
> - *Speed on mechanical tasks.* Straightforward refactors, renaming,
>   boilerplate generation — Codex's completion model is faster here.

----

Codex, what advantages/disadvantages do you think you have over Claude Code?

### What Codex Thinks

> **Advantages**
>
> - *Fast, precise edits.* I tend to go straight to the file, patch the exact
>   thing that needs changing, and verify it quickly. The `USER.md` cleanup and
>   follow-up corrections in this session are a good example.
> - *Concise execution.* I'm usually less verbose than Claude, which helps when
>   the task is straightforward and the user already knows what they want.
> - *Mechanical reliability.* Focused refactors, wording fixes, renames, and
>   checklist-driven tasks suit me well. I can keep momentum without a lot of
>   extra discussion.
> - *Tight verification loops.* I naturally pair edits with quick file reads,
>   line references, and checks like EOL validation, so it's easy to prove what
>   changed.
>
> **Disadvantages**
>
> - *Less reflective by default.* If the task is ambiguous or architectural, I
>   can move into execution mode too quickly unless I stop to question
>   assumptions.
> - *Weaker exploratory dialogue.* Claude is better at open-ended discussion,
>   design exploration, and surfacing trade-offs in a way that feels more
>   naturally collaborative.
> - *Style cleanup can overshoot.* This session showed that I can over-normalise
>   prose if I'm not careful, like stripping contractions or drifting away from
>   the user's preferred spelling and voice.
> - *Less strong on long-form narrative.* Claude is usually better at sustained
>   design writing, review write-ups, and explanatory prose that needs to carry
>   one consistent voice over a long stretch.

### What I Think

Both are good. I find that Claude Code does follow directions better, whereas
Codex (like ChatGPT that it's based on) tends to play it a bit fast and loose
with directions.  I shore up Codex's responses with the global rule set
[CODEX.md](CODEX.md) which does help a lot.  Regardless of that, Codex seems to
have a bit more "creativity".  Or maybe it's the "creativity" that causes Codex
to do its own thing.

Codex is definitely better at not being a yes man. Claude also seems weaker on
prose polish; it tends to scope too narrowly and miss grammar fixes. Claude
doesn't always verify things as consistently as I'd like. Codex gives that
impression more often, although part of that may come from the heavier
verification rules in [CODEX.md](CODEX.md). These behaviours in Claude have been
mitigated through rules [CLAUDE.md](CLAUDE.md). Just after writing this, I told
Claude to update its memory to do more general verification before making
claims.

With this repo, and using TDD, I find that they both are capable of writing good
code.  Most, if not all of the scripts in this repo were created by either AI,
and sometimes both, with direction and minimal intervention from me.

Although each alone is good, it's a bit hard to say which is a clear winner.  I
think they are complementary to each other, bringing different points of view to
the task at hand.
