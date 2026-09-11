#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	stub gh ''
}
teardown() { teardown_repo; }

@test "creates the four static labels on the given repository" {
	run "$SCRIPTS/setup-labels.sh" acme/widget
	[ "$status" -eq 0 ]
	[ "$(grep -c '^gh label create ' "$STUB_LOG")" -eq 4 ]
	for l in backport-manual release-only release-blocker tag-rc; do
		grep -q "^gh label create $l .* --force --repo acme/widget$" "$STUB_LOG"
	done
	! grep -q 'ci/full-e2e' "$STUB_LOG"
}
