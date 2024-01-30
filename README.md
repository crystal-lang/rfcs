# Crystal RFCs

The "RFC" (request for comments) process[^1] is intended to provide a consistent and controlled path for changes to Crystal or its ecosystem (such a `shards`) so that all stakeholders can be confident about the direction of the project.

Many changes, including bug fixes and documentation improvements can be implemented and reviewed via the normal GitHub pull request workflow.

Some changes though are "substantial", and we ask that these be put through a bit of a design process and produce a consensus among the Crystal community and the [Core Team].

## Table of Contents

[Table of Contents]: #table-of-contents

- [Table of Contents]
- [When you need to follow this process]
- [Before creating an RFC]
- [What the process is]
- [The RFC life-cycle]
- [Reviewing RFCs]
- [Implementing an RFC]

## When you need to follow this process

[When you need to follow this process]: #when-you-need-to-follow-this-process

You need to follow this process if you intend to make "substantial" changes to Crystal, Shards, any shard in the `crystal-lang` namespace, or the RFC process itself. What constitutes a "substantial" change is evolving based on community norms and varies depending on what part of the ecosystem you are proposing to change, but may include the following.

- Any semantic or syntactic change to the language that is not a bugfix.
- Removing language features, including those that are feature-gated.
- Substantial additions to the `stdlib`.

Some changes do not require an RFC:

- Rephrasing, reorganizing, refactoring, or otherwise "changing shape does not change meaning".
- Additions that strictly improve objective, numerical quality criteria (warning removal, speedup, better platform coverage, more parallelism, trap more errors, etc.)
- Small additions to the `stdlib`.

If you submit a pull request to implement a new feature without going through the RFC process, it may be closed with a polite request to submit an RFC first.

## Before creating an RFC

[Before creating an RFC]: #before-creating-an-rfc

A hastily-proposed RFC can hurt its chances of acceptance. Low quality
proposals, proposals for previously-rejected features, or those that don't fit into the near-term roadmap, may be quickly rejected, which can be demotivating for the unprepared contributor. Laying some groundwork ahead of the RFC can make the process smoother.

Although there is no single way to prepare for submitting an RFC, it is generally a good idea to pursue feedback from other project developers beforehand, to ascertain that the RFC may be desirable; having a consistent impact on the project requires concerted effort toward consensus-building.

The most common preparations for writing and submitting an RFC include talking the idea over on our [community channels]. You may file issues on this repo for discussion, but these are not actively looked at by the team.

As a rule of thumb, receiving encouraging feedback from long-standing project developers is a good indication that the RFC is worth pursuing.

## What the process is

[What the process is]: #what-the-process-is

In short, to get a major feature added to Crystal, one must first get the RFC merged into the RFC repository as a markdown file.

- Fork the RFC repo [RFC repository]
- Copy `0000-template.md` to `text/0000-my-feature.md` (where "my-feature" is descriptive). Don't assign an RFC number yet; This is going to be the PR number and we'll rename the file accordingly if the RFC is accepted.
- Fill in the RFC. It doesn't need to fill-in all the sections, but you can use the proposed format to guide your own thought process. Put care into the details: RFCs that do not present convincing motivation, demonstrate lack of understanding of the design's impact, or are disingenuous about the drawbacks or alternatives tend to be poorly-received.
- Submit a pull request. As a pull request the RFC will receive design feedback from the larger community, and the author should be prepared to revise it in response.
- Now that your RFC has an open pull request, use the issue number of the PR to update your `0000-` prefix to that number.
- Build consensus and integrate feedback. RFCs that have broad support are
much more likely to make progress than those that don't receive any comments. Feel free to reach out to the RFC assignee in particular to get help identifying stakeholders and obstacles.
- The [Core Team] will discuss the RFC pull request, as much as possible in the comment thread of the pull request itself. Offline discussion will be summarized on the pull request comment thread.
- RFCs rarely go through this process unchanged, especially as alternatives and drawbacks are shown. You can make edits, big and small, to the RFC to clarify or change the design, but make changes as new commits to the pull request, and leave a comment on the pull request explaining your changes. Specifically, **do not squash or rebase commits after they are visible on the pull request**.
- At some point, the RFC will collect enough approvals from the Core Team and it will be accepted (merged), or enough Core Team members will voiced their disapproval, in which case the RFC will be closed. If there's no clear consensus, the final discussion might happen in a Core Team meeting, in which case the decision will be summarized prior to the acceptance/rejection of the RFC.

## The RFC life-cycle

[The RFC life-cycle]: #the-rfc-life-cycle

Once an RFC becomes accepted then authors may implement it and submit the
feature as a pull request to the relevant repo. The RFC being approved is not a rubber stamp, and in particular still does not mean the feature will ultimately be merged; it does mean that in principle all the major stakeholders have agreed to the feature and are amenable to merging it.

Furthermore, the fact that a given RFC has been accepted implies nothing about what priority is assigned to its implementation, nor does it imply anything about whether a Crystal developer has been assigned the task of implementing the feature. While it is not _necessary_ that the author of the RFC also write the implementation, it is by far the most effective way to see an RFC through to completion: authors should not expect that other project developers will take on responsibility for implementing their accepted feature.

Modifications to accepted RFCs can be done in follow-up pull requests. We strive to write each RFC in a manner that it will reflect the final design of the feature; but the nature of the process means that we cannot expect every merged RFC to actually reflect what the end result will be at the time of the next major release.

In general, once accepted, RFCs should not be substantially changed. Only very minor changes should be submitted as amendments. More substantial changes should be new RFCs, with a note added to the original RFC.   Exactly what counts as a "very minor change" is up to the Core Team to decide.

## Reviewing RFCs

[Reviewing RFCs]: #reviewing-rfcs

While the RFC pull request is up, the Core Team may schedule meetings with the author and/or relevant stakeholders to discuss the issues in greater detail, and in some cases the topic may be discussed at a Core Team meeting. In either case a summary from the meeting will be posted back to the RFC pull request.

The Core Team makes final decisions about RFCs after the benefits and drawbacks are well understood. These decisions can be made at any time. When a decision is made, the RFC pull request will either be merged or closed. In either case, if the reasoning is not clear from the discussion in thread, the Core Team will add a comment describing the rationale for the decision.

## Implementing an RFC

[Implementing an RFC]: #implementing-an-rfc

Some accepted RFCs represent vital features that need to be implemented right away. Other accepted RFCs can represent features that can wait until some arbitrary developer feels like doing the work. Every accepted RFC has an associated issue tracking its implementation in the relevant repository; thus that associated issue can be assigned a priority via the triage process that the team uses for all issues.

The author of an RFC is not obligated to implement it. Of course, the RFC author (like any other developer) is welcome to post an implementation for review after the RFC has been accepted.

If you are interested in working on the implementation for an accepted RFC, but cannot determine if someone else is already working on it, feel free to ask (e.g. by leaving a comment on the associated issue).

[^1]: This process is based in [Rust's](https://github.com/rust-lang/rfcs).

[community channels]: https://crystal-lang.org/community
[RFC repository]: https://github.com/crystal-lang/rfcs
[Core Team]: https://crystal-lang.org/team
