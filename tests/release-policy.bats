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
	run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"all checks passed"* ]]
}

@test "a clean cherry-pick passes when nearby unchanged lines differ" {
	printf 'old\nunchanged\nrelease context\n' >config.txt
	git add config.txt
	git commit -qm "chore: add config"
	git branch -f "$BASE_REF" HEAD
	git push -q origin "$BASE_REF"

	printf 'old\nunchanged\nmain context\n' >config.txt
	git commit -qam "chore: update main context"
	printf 'fixed\nunchanged\nmain context\n' >config.txt
	git commit -qam "fix: update config"
	git push -q origin main
	backport_head

	run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"clean cherry-pick"* ]]

	echo extra >>config.txt
	git commit -q --amend --no-edit -a
	run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"content differs from origin"* ]]
}

@test "a clean backport passes regardless of its PR title" {
	commit "feat: add an option" option.txt >/dev/null
	git push -q origin main
	backport_head
	for title in "feat: add an option" "fix(api)!: rename the option" "Backport the option"; do
		PR_TITLE="$title" run "$SCRIPTS/release-policy.sh"
		[ "$status" -eq 0 ]
		[[ "$output" == *"all checks passed"* ]]
	done
}

@test "a commit without a cherry-pick trailer is refused" {
	git checkout -q release-0.5.0
	commit "fix: direct" d.txt >/dev/null
	git checkout -q --detach
	run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no '(cherry picked from commit"* ]]
}

@test "release-only skips provenance but demands a rationale" {
	git checkout -q release-0.5.0
	commit "fix: direct" d.txt >/dev/null
	git checkout -q --detach
	PR_LABELS_JSON='["release-only"]' PR_BODY="no reason given" run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Why not main"* ]]
	PR_LABELS_JSON='["release-only"]' PR_BODY=$'## Why not main\nmain removed this code' run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
}

@test "hand-resolved content needs the backport-manual label" {
	commit "fix: leak" fix.txt >/dev/null
	git push -q origin main
	backport_head
	echo extra >>fix.txt
	git commit -q --amend --no-edit -a
	run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"content differs from origin"* ]]
	PR_LABELS_JSON='["backport-manual"]' run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"accepted: backport-manual"* ]]
}

@test "a conflicting cherry-pick still requires the manual label" {
	commit "fix: main defaults" defaults.txt >/dev/null
	git push -q origin main
	git checkout -q "$BASE_REF"
	commit "chore: release defaults" defaults.txt >/dev/null
	git push -q origin "$BASE_REF"

	run git cherry-pick -x main
	[ "$status" -eq 1 ]
	echo resolved >defaults.txt
	git add defaults.txt
	git commit -qm "fix: main defaults" -m "(cherry picked from commit $(git rev-parse main))"

	run "$SCRIPTS/release-policy.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *"content differs from origin"* ]]
}

@test "GENERATED_PATHS removes paths from the advisory size count" {
	git checkout -q release-0.5.0
	mkdir -p vendor gen
	seq 1 500 >vendor/big.txt
	seq 1 500 >gen/big.txt
	git add -A
	git commit -q -m "chore: generated"
	git checkout -q --detach
	export PR_LABELS_JSON='["release-only"]' PR_BODY="Why not main: generated on the branch"
	run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"warn  500 changed lines"* ]]
	GENERATED_PATHS="vendor gen" run "$SCRIPTS/release-policy.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok    size: 0 changed lines"* ]]
}
