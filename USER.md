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
