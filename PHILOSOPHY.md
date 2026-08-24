# The JQ::Lite Philosophy

JQ::Lite began with a simple idea:

> **Software should adapt to its environment, not demand that the environment adapt to it.**

Modern software often assumes that the environment can be changed to suit the software.

Install another runtime. Add another library. Use a newer operating system. Build a container. Download a binary. Compile a dependency.

Sometimes that is the right answer.

But sometimes the machine in front of us is the machine we have.

It may be old. It may be minimal. It may be offline. It may be restricted. We may not have root access, a compiler, a package manager, or even a network connection.

Yet it may have Perl.

JQ::Lite exists for those machines too.

## Work with what is already there

A useful tool should not require rebuilding the world around it.

When possible, JQ::Lite prefers to work with the environment that already exists.

This is why portability is not an afterthought. It is part of the design.

We should ask:

> **Can we solve the problem with what the user already has?**

before asking:

> What else should the user install?

## Dependencies are design decisions

Dependencies are useful. They save enormous amounts of work, and good software is built on the work of others.

But every dependency is also a requirement placed on the user.

It is another thing that must exist, another thing that must remain compatible, another thing that may disappear, and another thing that may eventually need maintenance or security updates.

For JQ::Lite, keeping dependencies small is therefore not merely an implementation detail.

**Few dependencies are a feature.**

This does not mean that dependencies are bad.

It means that adding one should be a deliberate engineering decision rather than an automatic one.

## Portability is a feature

Performance can be measured.

Feature counts can be measured.

Portability is harder to see.

Its value often appears only years later, on a machine the original developer never expected anyone to use.

JQ::Lite values software that continues to work across different environments, different generations of systems, and different constraints.

Sometimes this means choosing a less fashionable solution.

Sometimes it means accepting that the fastest implementation is not necessarily the most useful implementation.

That is a tradeoff we are willing to consider.

## Compatibility is a promise

Once people build scripts and systems around a command-line tool, its behavior becomes part of their environment.

Output matters.

Exit status matters.

Error behavior matters.

Small details matter.

For this reason, compatibility should not be treated as an accidental property of JQ::Lite.

**Compatibility is a promise to users.**

Breaking that promise should require a better reason than making the implementation cleaner.

## Simplicity is not the absence of ambition

Software does not become better merely by becoming more complicated.

A clever implementation may be satisfying today and difficult to understand five years from now.

A boring implementation may survive.

JQ::Lite prefers code that future maintainers can understand, debug, repair, and trust.

That future maintainer may be someone else.

It may also be ourselves, many years from now.

> **Boring software survives.**

## Minimal dependencies do not mean minimal responsibility

Owning more of the implementation also means owning more of its mistakes.

Security vulnerabilities happen.

Bugs happen.

Design decisions turn out to be wrong.

Keeping a system small does not remove the responsibility to respond when that happens.

Security reports should be taken seriously. Failures should become regression tests. Mistakes should improve the design.

Simplicity is valuable only when it is accompanied by responsibility.

## Do not recreate jq

JQ::Lite is inspired by jq and aims to provide a useful jq-compatible subset.

It does not need to become jq.

The goal is not to reproduce every feature regardless of cost.

The goal is to provide enough expressive power to solve real problems while preserving the properties that make JQ::Lite useful in the first place.

When a new feature conflicts with portability, simplicity, reliability, or long-term maintainability, saying **no** may be the correct implementation.

Restraint is also engineering.

## Software should respect its users' constraints

Developers usually work on machines where installing another dependency is easy.

Users do not always have that luxury.

Their constraints may look strange from the developer's machine, but they are still real.

Old systems are real.

Offline systems are real.

Minimal containers are real.

Restricted production environments are real.

Machines that cannot simply be upgraded are real.

Good software does not judge those constraints.

It works with them.

## Build for people we will never meet

We cannot know where software will eventually run.

Someone may use JQ::Lite on a system we have never tested, for a purpose we never imagined, years after a particular design decision was made.

That uncertainty is not something portability can eliminate.

It is the reason portability matters.

The best outcome for JQ::Lite is not that users admire its implementation.

It is that the tool quietly solves their problem.

Perhaps they will never know who wrote it.

Perhaps they will never know that it is written in Perl.

That is fine.

Software has succeeded when it remains useful without requiring its author to be present.

---

JQ::Lite is an implementation.

The larger idea is simpler:

> **Build software for the machine people already have.**
>
> **Keep it understandable.**
>
> **Respect compatibility.**
>
> **Treat dependencies as decisions, not defaults.**
>
> **Take responsibility for what you build.**
>
> **Prefer software that remains useful over software that is merely impressive today.**

Technology changes quickly.

Useful software does not always have to.
