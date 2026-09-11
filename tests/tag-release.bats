#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	# gh api repos/<r>/commits/<sha>/status -> combined status with STUB_STATUS, or none
	stub gh 'if [ -n "${STUB_STATUS:-}" ]; then
	echo "{\"statuses\":[{\"context\":\"rc-validation\",\"state\":\"$STUB_STATUS\"}]}"
else
	echo "{\"statuses\":[]}"
fi'
}
teardown() { teardown_repo; }

@test "rc: tags rc2 when the branch head moved past rc1" {
	cut v0.5.0
	git checkout -q release-0.5.0
	sha=$(commit "fix: a")
	git push -q origin release-0.5.0
	git checkout -q main
	run "$SCRIPTS/tag-release.sh" release-0.5.0 rc
	[ "$status" -eq 0 ]
	[ "$(origin_ref v0.5.0-rc2)" = "$sha" ]
	grep -q '^tag=v0.5.0-rc2$' "$GITHUB_OUTPUT"
	grep -q '^last_rc=v0.5.0-rc1$' "$GITHUB_OUTPUT"
}

@test "rc: refuses when the head already carries an rc tag" {
	cut v0.5.0
	run "$SCRIPTS/tag-release.sh" release-0.5.0 rc
	[ "$status" -ne 0 ]
	[[ "$output" == *"already tagged v0.5.0-rc1"* ]]
}

@test "ga: refuses when the head is not the newest rc commit" {
	cut v0.5.0
	git checkout -q release-0.5.0
	commit "fix: a" >/dev/null
	git push -q origin release-0.5.0
	git checkout -q main
	run "$SCRIPTS/tag-release.sh" release-0.5.0 ga
	[ "$status" -ne 0 ]
	[[ "$output" == *"is not the commit of v0.5.0-rc1"* ]]
	[ -z "$(origin_ref v0.5.0)" ]
}

@test "ga: warns but tags when rc-validation is missing and not enforced" {
	cut v0.5.0
	run "$SCRIPTS/tag-release.sh" release-0.5.0 ga
	[ "$status" -eq 0 ]
	[[ "$output" == *"WARN"* ]]
	[ "$(origin_ref v0.5.0)" = "$(origin_ref v0.5.0-rc1)" ]
}

@test "ga: refuses when enforced and rc-validation is not success" {
	cut v0.5.0
	RC_VALIDATION_ENFORCE=true STUB_STATUS=failure run "$SCRIPTS/tag-release.sh" release-0.5.0 ga
	[ "$status" -ne 0 ]
	[[ "$output" == *"is 'failure', not 'success'"* ]]
	[ -z "$(origin_ref v0.5.0)" ]
}

@test "ga: tags when enforced and rc-validation is success" {
	cut v0.5.0
	RC_VALIDATION_ENFORCE=true STUB_STATUS=success run "$SCRIPTS/tag-release.sh" release-0.5.0 ga
	[ "$status" -eq 0 ]
	[ -n "$(origin_ref v0.5.0)" ]
}

@test "a released branch is read-only" {
	ga v0.5.0
	run "$SCRIPTS/tag-release.sh" release-0.5.0 rc
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only"* ]]
}

@test "branch name must be release-X.Y.Z" {
	run "$SCRIPTS/tag-release.sh" main rc
	[ "$status" -ne 0 ]
	[[ "$output" == *"branch must be release-X.Y.Z"* ]]
}
