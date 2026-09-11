#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	stub gh 'case "$*" in
	"api orgs/acme/teams/release-managers --jq .id") echo 42 ;;
	*) : ;;
esac'
}
teardown() { teardown_repo; }

@test "dry run resolves team and app ids and fills the required checks" {
	run "$SCRIPTS/apply-rulesets.sh" --repo acme/widget --team release-managers --app-id 4870505 \
		--checks "pr-ci / build,[OP] PR CI@3323144" --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *'"actor_id": 42'* ]]
	[[ "$output" == *'"actor_id": 4870505'* ]]
	[[ "$output" == *'"context": "pr-ci / build"'* ]]
	[[ "$output" == *'"integration_id": 3323144'* ]]
	[[ "$output" == *'"context": "release-policy / release-policy"'* ]]
	[[ "$output" == *"POST repos/acme/widget/rulesets"* ]]
	[[ "$output" != *"__TEAM_ID__"* ]]
	[[ "$output" != *"__APP_ID__"* ]]
}

@test "without --checks only release-branches keeps a required_status_checks rule" {
	run "$SCRIPTS/apply-rulesets.sh" --repo acme/widget --team release-managers --app-id 1 --dry-run
	[ "$status" -eq 0 ]
	[ "$(grep -c '"type": "required_status_checks"' <<<"$output")" -eq 1 ]
	[[ "$output" == *'"context": "release-policy / release-policy"'* ]]
}

@test "team and app id are required" {
	run "$SCRIPTS/apply-rulesets.sh" --repo acme/widget --dry-run
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage:"* ]]
}
