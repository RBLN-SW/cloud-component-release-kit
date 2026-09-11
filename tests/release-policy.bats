#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	cut v0.5.0
	export BASE_REF=release-0.5.0 PR_NUMBER=7
}
teardown() { teardown_repo; }

# Cherry-pick main's HEAD onto release-0.5.0 with -x and leave HEAD detached
# there, the way the PR head checkout looks in CI. origin's release-0.5.0 stays
# at the cut, so base..HEAD is exactly the PR's commits.
backport_head() {
	local src
	src=$(git rev-parse main)
	git checkout -q release-0.5.0
	git cherry-pick -x "$src" >/dev/null
	git checkout -q --detach
}

@test "an identical cherry-pick with a trailer passes every check" {
	commit "fix: leak" fix.txt >/dev/null
	git push -q origin main
	backport_head
	PR_TITLE="fix: leak" run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"all checks passed"* ]]
}

@test "a feat title is refused on a release branch" {
	commit "feat: thing" f.txt >/dev/null
	git push -q origin main
	backport_head
	PR_TITLE="feat: thing" run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"title: type must be one of"* ]]
}

@test "a breaking marker is refused on a release branch" {
	commit "fix!: thing" f.txt >/dev/null
	git push -q origin main
	backport_head
	PR_TITLE="fix!: thing" run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"breaking change marker"* ]]
}

@test "a commit without a cherry-pick trailer is refused" {
	git checkout -q release-0.5.0
	commit "fix: direct" d.txt >/dev/null
	git checkout -q --detach
	PR_TITLE="fix: direct" run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no '(cherry picked from commit"* ]]
}

@test "release-only skips provenance but demands a rationale" {
	git checkout -q release-0.5.0
	commit "fix: direct" d.txt >/dev/null
	git checkout -q --detach
	PR_TITLE="fix: direct" PR_LABELS_JSON='["release-only"]' PR_BODY="no reason given" run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Why not main"* ]]
	PR_TITLE="fix: direct" PR_LABELS_JSON='["release-only"]' PR_BODY=$'## Why not main\nmain removed this code' run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
}

@test "hand-resolved content needs the backport-manual label" {
	commit "fix: leak" fix.txt >/dev/null
	git push -q origin main
	backport_head
	echo extra >>fix.txt
	git commit -q --amend --no-edit -a
	PR_TITLE="fix: leak" run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"content differs from origin"* ]]
	PR_TITLE="fix: leak" PR_LABELS_JSON='["backport-manual"]' run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"accepted: backport-manual"* ]]
}

@test "GENERATED_PATHS removes paths from the advisory size count" {
	git checkout -q release-0.5.0
	mkdir -p vendor gen
	seq 1 500 >vendor/big.txt
	seq 1 500 >gen/big.txt
	git add -A
	git commit -q -m "chore: generated"
	git checkout -q --detach
	export PR_TITLE="chore: generated" PR_LABELS_JSON='["release-only"]' PR_BODY="Why not main: generated on the branch"
	run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"warn  500 changed lines"* ]]
	GENERATED_PATHS="vendor gen" run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok    size: 0 changed lines"* ]]
}
