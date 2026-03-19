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

There's no doubt, that AI is amazing at helping you write stuff.  However, if
you want to write something that's maintainable you should not just tell it to
do whatever it wants however it wants. You need to give it some guidance. This
repo is to help give it guidance, but it is not just the AI that needs guidance.
You the User require guidance in how to use the AI. That is what this file is
for.

## Generate a Plan

When you have a plan, you know when things are done. Figure out what you want
and get the AI understand what that is. Use the AI to help you with this. It can
be a great sounding board to figure out what it is you actually want.

## Break Down the Plan into Smaller Chunks

When you have a big plan, you need to break it down into smaller, more
manageable pieces. This helps in visualizing the entire system. This also helps
to see progress by seeing when the individual pieces are done. This is not just
for writing with AI, this is a general philosophy of doing things.

## For Complex Items, Make the Plan a Living Document

This is your design document which list what you are attempting to accomplish,
possible design specs in a mixture of text and maybe UML to help visualize what
you're trying to do and a list of subtasks to get it done.  The tasks should be
allowed to be modified by the AI to mark them as complete as they are completed.

This document should describe the MVP (minimum viable product).

## Try and Avoid Scope Creep

If you are finding that your scope is widening, stop.  Add to your design
document a section that lists things that could/should be added.  This also
keeps you from forgetting about ideas you had.

Stick with your MVP.  Once the MVP is complete you can go back and add these
features later. It's a good idea to also keep track of bugs in a similar manner.
These are just more task lists for you and the AI to suss over later.

## Read What the AI is Thinking

The AI thinks a lot. What it thinks is very useful sometimes. It can show you
when it is going off the rails, looping, or doing something that is not a good
idea, or not what you intended. Reading this output can help you get ahead of
problems later on by giving it missing information which it is notorious for
filling in with what ever comes into its net.  You don't have to read the entire
thing, just skim it.

You can actually steer Codex by typing in a prompt and pressing control enter.
Enter just queues it, to be delivered at the end of the current prompt.  If you
accidentally put it in the queue, either press Ctrl-Enter or press the `steer`
button. In Claude you just type in a prompt and hit enter.  There is no queueing
in Claude. Both get to prompt as soon as it's able to, usually when it stops
thinking about one thing and uses a tool to do something. If you ask it a
question related to what it's doing, this repo has it so that it stops until you
are satisfied. However if you just state something, it'll incorporate it into
what it is doing already.

If you're finding that it's looping or is stuck some way and it's using a lot of
tokens, just hit the stop button and write a prompt to clarify the issue or ask
it questions as to what it's doing.  I think you do cause the AI to lose a
little of what it was doing while thinking, but this can save you from running
out of tokens due to some logic loop.

## `git` is Your Friend

You should always get your AI to commit once it is finished a task. This is
general behavior for any developer but for AI it's crucial because if it
does something bad the entire run is not necessarily compromised, especially
when it was told to do several tasks at once.

It's also a good idea when you are going to do something risky (AI or not) so
that you can see what you changed and potentially roll back.

## TDD is Your Friend

Test Driven Development has always been a good idea but even more so with the
advent of using AI to write code. That's because AI needs a target and needs to
know when it's reached that target and when it's not. You don't have to write
the tests yourself, you can get the AI to write it based on the requirements.
You can go over those tests to see if it covers everything that you need. That
way you can go for a coffee and come back and hopefully things are done if it
hasn't stopped to ask you a question.

## Logging and Replay

For complicated tasks, it can be useful to create logs to see what is coming in
and what is going out of whatever object you're testing. These logs can be
critical for writing robust tests as you can retrofit them to replay the
situation and see if the output is what was intended. This is also good for
verifying that changes to have not compromised your invariants that you relying
on.

## Self Reflection

I've written a script called AI-transcript.py that will allow you to see
conversation between you and the AI. You can use this actually to help the AI
reflect upon what it has done and possibly give it something to write down in
its memory (either global project memory) so that it doesn't do it again
(mostly).
