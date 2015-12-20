
# Helpers
# Put this in your .bashrc or something:
#
#   source ~/go/src/github.com/USER/PROJECT/tools/gerrit-helpers.sh
#
# Requirements:
#   jq, ssh

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

# prints the current patchset for a change
clps() {
  cl=$1
  ssh review.example.com gerrit query --current-patch-set --format=JSON $cl |\
  	jq -r .currentPatchSet.number |\
  	head -n1
}

# prints the current ref for a change. i.e. `refs/changes/99/99/4`
clref() {
  cl=$1
  ssh review.example.com gerrit query --current-patch-set --format=JSON $cl |\
  	jq -r .currentPatchSet.ref |\
  	head -n1
}

# marks the specified change as ready for review. PTAL == please take a look
ptal() {
  cl=$1
  ps=$(clps $cl)
  ssh review.example.com gerrit review $cl,$ps --ready +2
}

# checks out the specified patchset
clco() {
  cl=$1
  ref=$(clref $cl)
  git fetch review $ref && git checkout FETCH_HEAD
}

# cherry-picks the specified patchset
clcp() {
  cl=$1
  ref=$(clref $cl)
  git fetch review $ref && git cherry-pick FETCH_HEAD
}

# updates and switches to the master
clmaster() {
  git fetch review master && git checkout FETCH_HEAD
}

# run the verify command on the specified CL
clverify() {
  cl=$1
  dir=$(cd $(git rev-parse --git-dir)/..; pwd)
  (cd $dir; go run ./tools/verify.go --cl $cl)
}


