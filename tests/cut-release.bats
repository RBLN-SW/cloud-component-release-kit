#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	stub gh '' # gh label create: log only
}
teardown() { teardown_repo; }

@test "minor cuts release-X.(Y+1).0 from origin/main and tags rc1" {
	ga v0.4.4
	sha=$(commit "feat: new thing")
	git push -q origin main
	run "$SCRIPTS/cut-release.sh" minor
	[ "$status" -eq 0 ]
	[ "$(origin_ref release-0.5.0)" = "$sha" ]
	[ "$(origin_ref v0.5.0-rc1)" = "$sha" ]
	grep -q '^gh label create backport release-0.5.0 ' "$STUB_LOG"
	grep -q '^version=0.5.0$' "$GITHUB_OUTPUT"
	grep -q '^branch=release-0.5.0$' "$GITHUB_OUTPUT"
	grep -q '^tag=v0.5.0-rc1$' "$GITHUB_OUTPUT"
}

@test "patch cuts from the newest GA tag, not from main" {
	ga_sha=$(git rev-parse HEAD)
	ga v0.4.4
	commit "feat: not for the patch" >/dev/null
	git push -q origin main
	run "$SCRIPTS/cut-release.sh" patch
	[ "$status" -eq 0 ]
	[ "$(origin_ref release-0.4.5)" = "$ga_sha" ]
	[ "$(origin_ref v0.4.5-rc1)" = "$ga_sha" ]
}

@test "patch is refused when its parent is not the newest GA" {
	ga v0.4.4
	commit "feat: x" >/dev/null
	git push -q origin main
	ga v0.5.0
	run "$SCRIPTS/cut-release.sh" patch --version 0.4.5
	[ "$status" -ne 0 ]
	[[ "$output" == *"newest GA is v0.5.0"* ]]
	[ -z "$(origin_ref release-0.4.5)" ]
}

@test "the first release needs --version" {
	run "$SCRIPTS/cut-release.sh" minor
	[ "$status" -ne 0 ]
	[[ "$output" == *"pass --version"* ]]
	run "$SCRIPTS/cut-release.sh" minor --version 0.1.0
	[ "$status" -eq 0 ]
	[ -n "$(origin_ref v0.1.0-rc1)" ]
}

@test "refuses when the release branch already exists on origin" {
	ga v0.4.4
	git branch release-0.5.0
	git push -q origin release-0.5.0
	run "$SCRIPTS/cut-release.sh" minor
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "a version that does not sort above the newest GA is refused" {
	ga v0.4.4
	run "$SCRIPTS/cut-release.sh" minor --version 0.3.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not sort above"* ]]
}

@test "kind must be minor, patch or major" {
	run "$SCRIPTS/cut-release.sh" hotfix
	[ "$status" -ne 0 ]
	[[ "$output" == *"kind must be"* ]]
}
