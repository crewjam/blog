+++
date = "2015-08-27T16:06:56-07:00"
title = "Gerrit Code Review"
description = "How and why we use Gerrit"
image = "/images/Landscape_01.jpg"
+++

At work, we've been long-time users of Gerrit for code review. We recently started a new project with a new team and had an opportunity to reevaluate that choice against other workflows, particularly Github Pull Requests.

## Collectivist Approach

I'm a strong believer in a collective approach to team decision making (you could call it the anarchist (with a capital "A"), but that freaks people out). Particularly around tooling, leaders should not be perscriptive. We should, together, pick the tools that work for us. I *prima facie* reject being told what tools our team will use, and avoid demanding teams use particular tools whenever possible. (This applies equally to security teams as well as development teams, although I'm talking about development teams here.)

![](/images/hippies.jpg) 

Part of the collective approach is that code review should be done one a peer-to-peer basis, rather than by a chief programmer. A code review process which everyone buys into will be mutally supportive and has been show to be effective at stopping bugs early. A top-down code review process tends towards the demoralizing and the oppressive.

It is in this context that we set out to decide how we were going to work on this new project.

## What we want

In the course of the discussion about code review, we have come to realize that we want:

- Code review to happen before code is merged (pre-commit).
- Support for revising changes.
- Workflow support that makes review efficient.
- A clean commit history.

![](/images/gerrit_workflow.png)

## vs. Printout Review

We could have built a process around *printout review* (my term) where we get together and look at the code as a whole every once in a while. There are some people advocating for this and some tools that support it (you can do it with GitHub comments, for example). 

We reject this approach because it is [too time consuming and not suficiently effective](http://smartbear.com/SmartBear/media/pdfs/11_Best_Practices_for_Peer_Code_Review.pdf) at finding bugs.

Before a commit has landed you still have plenty of time to discuss coding choices, make small suggestions, and so on. With printout review, there is inertia preventing even small changes.

And small changes matter. Getting names consistent & descriptive allows a large codebase to be immediately understood. Getting spelling and whitespace correct makes the codebase grepable and inspires confidence.

## vs. Pull Requests

Revising a change before it lands is an important part of our process. The general workflow of a change is something like this:

1. You write some code.
2. You ask for a review.
3. The reviewer makes some comments
4. You make some changes.
5. You ask for a second review.
6. The reviewer gives a thumbs up.
7. The code is merged.

The Github Pull Request workflow seems to be based on the idea that steps 4 and 5 are rare. It assumes that changes will not routinely be modified after their initial review.

We found that we were revising commits **constantly**. So with pull requests we'd have a feature branch like:

    REVXXXX1 frob: adjust the grob to be more grobular
    REVXXXX2 fix review comments
    REVXXXX3 fix typos

And each of those revisions would have a few comments here and there. 

Of course we don't want `REVXXXX2` and `REVXXXX3` in the commit history, so we'd squish the commits into one before we merged them. And when we squish the history *poof!* our comments are gone.

![](/images/gerrit_github.png)

In the screenshot above we see a change made using the pull request flow. There are three commits: an initial change (not shown) and two revisions in response to comments (yellow box). The final commit (red box) is a squished commit combining the three previous. Inline comments from the intermediate changes are lost. 

We discovered that we need first-class support for revising changes. With pull requests revisions are clumsy at best.

## Gerrit

Next we tried Gerrit. Revising a change very easy and natural. In Gerrit each change has a number of revisions and the revision of changes is a first-class concept.

![](/images/gerrit_gerrit.png)

We have found the using Gerrit promotes a lot of nice things:

- We get reasonable commit history.
- Our code is easy to read because continuity errors get fixed. (i.e. "You called it a `FrobServer` over there but here it is `frob_handler`")
- Our master branch is ~~always~~ usually working.
- Reviews happen quickly because people know what to review.
- The tools are easy (once you get used to 'em).

## Review Workflow

Code review works much better when reviews can happen quickly. We were getting slowed down by spending a lot of time tracking the state of various reviews. "Are you ready for be to review 174 yet?" 

We discovered that our changes were in one of just a few states:

 - **Not Ready** - changes that were pushed for backup or other non-review reasons.
 - **Work In Progress** - a partially commited change where the author wanted early feedback
 - **Ready for Review** - complete work that needs review.
 - **Needs Revision** - reviewed work that needs changed before it is merged.
 - **Ready to Merge** - work that is reviewed and ready to go.

When we tried GitHub, we used labels like `needs-review` and `needs-refactor` to indicate the state of a PR. This was natural, although we found reviewers were forgetting to set `needs-refactor` after doing a review. This was slightly forced, but certainly workable.

With Gerrit the labels scheme fits this approach very naturally. As is typical for Gerrit, we use the built-in `Code-Review` label set to *+2* for ready to merge. We created a custom label `Ready` with the following meaning:

- *-1* - broken, please ignore
- *0* - not ready for review
- *+1* - work in progress, feedback requested
- *+2* - ready for final review

From the Gerrit reviwers and authors can easily understand what work is waiting for them:

![](/images/gerrit_dashboard.png)












