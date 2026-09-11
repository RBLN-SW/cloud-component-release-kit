#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	# shellcheck source=../scripts/lib.sh
	. "$SCRIPTS/lib.sh"
}
teardown() { teardown_repo; }

@test "last_ga_tag ignores rc tags and sorts by version" {
	git tag v0.9.0
	git tag v0.10.0
	git tag v0.10.1-rc1
	[ "$(last_ga_tag)" = v0.10.0 ]
}

@test "last_ga_tag is empty when only rc tags exist" {
	git tag v1.0.0-rc1
	[ -z "$(last_ga_tag)" ]
}

@test "prev_ga_tag returns the highest GA below the given version" {
	git tag v0.9.0
	git tag v0.10.0
	git tag v0.10.1
	[ "$(prev_ga_tag v0.10.1)" = v0.10.0 ]
	[ "$(prev_ga_tag v0.10.0)" = v0.9.0 ]
	[ -z "$(prev_ga_tag v0.9.0)" ]
}

@test "last_rc_tag picks the highest rc of one version" {
	git tag v0.10.0-rc1
	git tag v0.10.0-rc2
	git tag v0.10.0-rc10
	git tag v0.11.0-rc1
	[ "$(last_rc_tag 0.10.0)" = v0.10.0-rc10 ]
}

@test "next_version bumps by kind" {
	[ "$(next_version minor v0.4.4)" = 0.5.0 ]
	[ "$(next_version patch v0.4.4)" = 0.4.5 ]
	[ "$(next_version major v0.4.4)" = 1.0.0 ]
}

@test "commit_status_state reads the context state through gh" {
	stub gh 'echo "{\"statuses\":[{\"context\":\"rc-validation\",\"state\":\"success\"}]}"'
	[ "$(commit_status_state abc rc-validation)" = success ]
	[ "$(commit_status_state abc other)" = none ]
}
