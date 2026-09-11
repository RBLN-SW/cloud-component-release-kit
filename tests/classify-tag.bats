#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	stub gh 'if [ -n "${STUB_STATUS:-}" ]; then
	echo "{\"statuses\":[{\"context\":\"rc-validation\",\"state\":\"$STUB_STATUS\"}]}"
else
	echo "{\"statuses\":[]}"
fi'
}
teardown() { teardown_repo; }

@test "an rc tag on its release branch is classified rc" {
	cut v0.5.0
	run "$SCRIPTS/classify-tag.sh" v0.5.0-rc1
	[ "$status" -eq 0 ]
	[[ "$output" == *"kind=rc"* ]]
	[[ "$output" == *"version=0.5.0"* ]]
	[[ "$output" == *"branch=release-0.5.0"* ]]
	[[ "$output" == *"last_rc=v0.5.0-rc1"* ]]
}

@test "a GA tag on the newest rc commit is classified ga with that rc" {
	ga v0.5.0
	run "$SCRIPTS/classify-tag.sh" v0.5.0
	[ "$status" -eq 0 ]
	[[ "$output" == *"kind=ga"* ]]
	[[ "$output" == *"last_rc=v0.5.0-rc1"* ]]
	[[ "$output" == *"continuing because RC_VALIDATION_ENFORCE"* ]]
}

@test "a GA tag that is not the newest rc commit is refused" {
	cut v0.5.0
	git checkout -q release-0.5.0
	commit "fix: a" >/dev/null
	git tag -a v0.5.0 -m ga
	git push -q origin release-0.5.0 v0.5.0
	git checkout -q main
	run "$SCRIPTS/classify-tag.sh" v0.5.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"Nothing was published"* ]]
}

@test "a tag outside its release branch is refused" {
	cut v0.5.0
	commit "feat: on main" >/dev/null
	git tag -a v0.5.0-rc2 -m rc2
	git push -q origin main v0.5.0-rc2
	run "$SCRIPTS/classify-tag.sh" v0.5.0-rc2
	[ "$status" -ne 0 ]
	[[ "$output" == *"is not a commit of release-0.5.0"* ]]
}

@test "a tag whose release branch does not exist is refused" {
	git tag -a v0.5.0-rc1 -m rc1
	git push -q origin v0.5.0-rc1
	run "$SCRIPTS/classify-tag.sh" v0.5.0-rc1
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not exist on origin"* ]]
}

@test "ga is refused when enforced and the status is not success" {
	ga v0.5.0
	RC_VALIDATION_ENFORCE=true STUB_STATUS=error run "$SCRIPTS/classify-tag.sh" v0.5.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"'error' means the validation infrastructure failed"* ]]
}

@test "malformed tags are refused" {
	run "$SCRIPTS/classify-tag.sh" release-0.5.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"tag must be vX.Y.Z or vX.Y.Z-rcN"* ]]
}
