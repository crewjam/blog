+++
date = "2015-08-27T15:40:05-07:00"
title = "Command line helpers for Gerrit"
image = "/images/il_570xN.483625064_rldm.jpg"
+++

At work we use Gerrit for pre-commit code review. I [described the reasons previously](/gerrit-code-review/). Here are some handy shell helpers to make working with gerrit reviews a bit quicker. The full script is [here](/gerrit-helpers.sh)

Assumptions:

- These examples assume you have a code review server at `review.example.com`, although obviously yours will be somewhere else.

- These examples assume you have a git remote named `review` that defines 
  your code review server. A partial `.git/config` might look like:
  
  ```git
  [remote "review"]
    url = ssh://alice@review.example.com/project
    fetch = +refs/heads/*:refs/remotes/review/*
    push = HEAD:refs/for/master
  ```

- You have `git` (obviously), `ssh`, and `jq` (from [here](https://stedolan.github.io/jq/)) in your path.

## Basic Information

Show basic information about a single CL, or the currently open CLs. Useful to know the general status of a project.

```bash
# prints information about the specified patchset or all patchsets
cl() {
  n=$1
  if [ ! -z "$n" ] ; then
    ssh review.example.com gerrit query --current-patch-set $n
    return $?
  fi
  ssh review.example.com gerrit query --format=JSON --current-patch-set "is:open" | (
    while read line
    do
      n=$(echo $line | jq -r '.number')
      app=$(echo $line | jq '.currentPatchSet.approvals[]? | .by.username + ":" + .type + " " + .value')
      echo $n $(echo $line | jq -r '.subject') $app
    done
  )
  
}
```

Here is what it looks like right now when I run it against our code review server:

![](/images/gerrit_helpers_cl.png)

Viewing a single change (this could be a lot prettier!):

![](/images/gerrit_helpers_cl_2.png)

## Switching Around

Various functions for switching the current checkout to a specific change or with to the master.

Checks out the specified patchset:

```bash
# checks out the specified patchset
clco() {
  cl=$1
  ref=$(clref $cl)
  git fetch review $ref && git checkout FETCH_HEAD
}
```

Cherry-picks the specified patchset:

```bash
# cherry-picks the specified patchset
clcp() {
  cl=$1
  ref=$(clref $cl)
  git fetch review $ref && git cherry-pick FETCH_HEAD
}
```

Updates and switches to the master:

```bash
# updates and switches to the master
clmaster() {
  git fetch review master && git checkout FETCH_HEAD
}
```

## Workflow

The `ptal` ("please take a look") command is a handy way to ask for a review. We use a custom flag called `Ready` that has the following semantics:

- *-1* - broken, lease ignore
- *0* - not ready for review
- *+1* - work in progress, feedback requested
- *+2* - ready for final review

This command marks the specified change as ready for review. 

```bash
# marks the specified change as ready for review. PTAL == please take a look
ptal() {
  cl=$1
  ps=$(clps $cl)
  ssh review.example.com gerrit review $cl,$ps --ready +2
}
```

## Testing

I'll write more about how we run tests and verify them in a future post, but for now just know that somebody has to vote `Verified` to `+1`, meaning that the tests pass, before we land a change. This command triggers tests for the specified CL:

```bash
# run the verify command on the specified CL
clverify() {
  cl=$1
  dir=$(cd $(git rev-parse --git-dir)/..; pwd)
  (cd $dir; go run ./tools/verify.go --cl $cl)
}
```

## Helper Functions

These little helpers were used above.

Prints the current patchset for a change, i.e. `2`:

```bash
# prints the current patchset for a change
clps() {
  cl=$1
  ssh review.example.com gerrit query --current-patch-set --format=JSON $cl |\
    jq -r .currentPatchSet.number |\
    head -n1
}
```

Prints the current ref for a change. i.e. `refs/changes/57/57/2`:

```bash
# prints the current ref for a change. i.e. `refs/changes/99/99/4`
clref() {
  cl=$1
  ssh review.example.com gerrit query --current-patch-set --format=JSON $cl |\
    jq -r .currentPatchSet.ref |\
    head -n1
}
```


