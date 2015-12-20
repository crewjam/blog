+++
date = "2015-08-27T16:06:56-07:00"
draft = true
title = "Gerrit Code Review"
description = "How and why we use Gerrit"
image = "/images/EA-6B_Prowler_maintenance_check.jpg"
+++

At work, we've been long-time users of Gerrit for code review. We recently started a new project with a new team and had an opportunity to reevaluate that choice against other workflows, particularly Github Pull Requests.

## Aside: Anarchy!

I'm a strong believer in an Anarchist approach to decision making around tooling. We should all **together** pick the tools that work for us. I *prima facie* reject being told what tools out team will use. (This applies to security teams as well as development teams.)

![](/images/not-how-it-works-300x300.jpg) 

Part of anarchy is that reviews should be done one a peer-to-peer basis. We're all in this together. The time to establish

## What we want

We have come to realize that we want:

- Review to happen before code is merged.
- Support for revising changes.
- Workflow support that makes review efficient.
- A clean commit history.

## vs. Printout Review

We could have built a process around *printout review* (my term) where we get together and look at the code as a whole every once in a while. There are some people advocating for this and some tools that support it (you can do it with GitHub comments). 

We reject this approach because it is [too time consuming and not suficiently effective](http://smartbear.com/SmartBear/media/pdfs/11_Best_Practices_for_Peer_Code_Review.pdf).

Before a commit has landed you still have plenty of time to discuss coding choices, make small suggestions, and so on. With printout review, there is inertia preventing even small changes.

## Revising Changes

For us, the general workflow of a change is something like this:

1. You write some code.
2. You ask for a review.
3. The reviewer makes some comments
4. You make some changes.
5. You ask for a second review.
6. The reviewer gives a thumbs up.
7. The code is merged.

The Pull Request workflow seems to be based on the idea that steps 4 and 5 are rare. It assumes that changes will not routinely be modified after their initial review.

However we found that we were revising commits *CONSTANTLY*. So with pull requests we'd have a feature branch like:

    REVXXXX1 frob: adjust the grob to be more grobular
    REVXXXX2 fix review comments
    REVXXXX3 fix typos

And each of those revisions would have a few comments here and there. 

Of course we don't want `REVXXXX2` and `REVXXXX3` in the commit history, so we'd squish the commits into one before we merged them. And when we squish the history *poof!* our comments are gone.

![](/images/gerrit_pr_revision.png)

Gerrit, on the other hand, makes revising a change very easy and natural. In Gerrit each change has a number of revisions and the revision of changes is a natural part of the environment.

![](/images/gerrit_revised_cl.png)

## Review Workflow

Code review works much better when reviews can happen quickly. We noticed that our changes were in one of just a few states:

 - **Not Ready** - changes that were pushed for backup or other non-review reasons.
 - **Work In Progress** - a partially commited change where the author wanted early feedback
 - **Ready for Review** - complete work that needs review.
 - **Needs Revision** - reviewed work that needs changed before it is merged.
 - **Ready to Merge** - work that is reviewed and ready to go.

When we tried GitHub, we used labels like `needs-review` and `needs-refactor` to indicate the state of a PR. This was natural, although we found reviewers were forgetting to set `needs-refactor` after doing a review. This was slightly forced, but certainly workable.

With Gerrit the labels scheme fits this approach very naturally. The built-in `Code-Review` label is set to *+2* for ready to merge. We created a custom label `Ready` with the following meaning:

- *-1* - broken, lease ignore
- *0* - not ready for review
- *+1* - work in progress, feedback requested
- *+2* - ready for final review

From the Gerrit reviwers and authors can easily understand what work is waiting for them:

![](/images/gerrit_dashboard.png)

## Upsides

We have found the using Gerrit promotes a lot of nice things:

- We get reasonable commit history.
- Our code is easy to read because continuity errors get fixes. (i.e. "You called it a `FrobServer` over there but here it is `frob_handler`")
- Our master branch is ~~always~~ usually working.
- Reviews happen quickly because people know what review 
- Although the tooling takes some getting















