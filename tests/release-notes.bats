#!/usr/bin/env bats
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "groups by type, keeps a backport whose origin is outside the range, appends the extra file" {
	ga v0.4.0
	commit "feat: shiny" a.txt >/dev/null
	commit "fix: leak" b.txt >/dev/null
	commit "docs: readme" c.txt >/dev/null
	git push -q origin main
	cut v0.5.0
	late=$(commit "fix: late" d.txt)
	git push -q origin main
	git checkout -q release-0.5.0
	git cherry-pick -x "$late" >/dev/null
	git tag -a v0.5.0-rc2 -m rc2
	git tag -a v0.5.0 -m ga
	git checkout -q main
	echo "| extra | row |" >"$TEST_TMP/extra.md"
	RELEASE_NOTES_EXTRA="$TEST_TMP/extra.md" run "$SCRIPTS/release-notes.sh" v0.5.0 v0.4.0 "$TEST_TMP/notes.md"
	[ "$status" -eq 0 ]
	notes=$(cat "$TEST_TMP/notes.md")
	[[ "$notes" == *"## New Features"*"- feat: shiny"* ]]
	[[ "$notes" == *"## Improvements"*"- docs: readme"* ]]
	[[ "$notes" == *"## Fixed Issues"*"- fix: leak"* ]]
	[ "$(grep -c 'fix: late' "$TEST_TMP/notes.md")" -eq 1 ]
	[[ "$notes" == *"| extra | row |"* ]]
	[[ "$notes" == *"Changes since v0.4.0"* ]]
	[[ "$notes" == *"https://github.com/acme/widget/commit/"* ]]
}

@test "a main commit already shipped as a backport in the previous GA is dropped" {
	ga v0.4.0
	cut v0.5.0
	late=$(commit "fix: late" d.txt)
	git push -q origin main
	git checkout -q release-0.5.0
	git cherry-pick -x "$late" >/dev/null
	git tag -a v0.5.0 -m ga
	git checkout -q main
	commit "feat: next" e.txt >/dev/null
	cut v0.6.0
	git tag -a v0.6.0 -m ga
	run "$SCRIPTS/release-notes.sh" v0.6.0 v0.5.0 "$TEST_TMP/notes.md"
	[ "$status" -eq 0 ]
	! grep -q 'fix: late' "$TEST_TMP/notes.md"
	grep -q 'feat: next' "$TEST_TMP/notes.md"
}

@test "breaking commits get their own section and PR numbers become links" {
	ga v0.4.0
	commit "feat!: drop v1 api (#12)" a.txt >/dev/null
	cut v0.5.0
	git tag -a v0.5.0 -m ga
	run "$SCRIPTS/release-notes.sh" v0.5.0 v0.4.0 "$TEST_TMP/notes.md"
	[ "$status" -eq 0 ]
	grep -q '## ⚠ Breaking Changes' "$TEST_TMP/notes.md"
	grep -q '\[#12\](https://github.com/acme/widget/pull/12)' "$TEST_TMP/notes.md"
}

@test "without a previous tag the whole history is the range" {
	commit "feat: first" a.txt >/dev/null
	cut v0.1.0
	git tag -a v0.1.0 -m ga
	run "$SCRIPTS/release-notes.sh" v0.1.0 "" "$TEST_TMP/notes.md"
	[ "$status" -eq 0 ]
	grep -q 'feat: first' "$TEST_TMP/notes.md"
	grep -q '_Generated for v0.1.0._' "$TEST_TMP/notes.md"
}

@test "an executable RELEASE_NOTES_EXTRA is run and its output appended" {
	commit "feat: first" a.txt >/dev/null
	cut v0.1.0
	git tag -a v0.1.0 -m ga
	printf '#!/usr/bin/env bash\necho "| generated | $GITHUB_REPOSITORY |"\n' >"$TEST_TMP/extra.sh"
	chmod +x "$TEST_TMP/extra.sh"
	RELEASE_NOTES_EXTRA="$TEST_TMP/extra.sh" run "$SCRIPTS/release-notes.sh" v0.1.0 "" "$TEST_TMP/notes.md"
	[ "$status" -eq 0 ]
	grep -q '| generated | acme/widget |' "$TEST_TMP/notes.md"
}

@test "a RELEASE_NOTES_EXTRA that is neither executable nor file fails" {
	commit "feat: first" a.txt >/dev/null
	cut v0.1.0
	git tag -a v0.1.0 -m ga
	RELEASE_NOTES_EXTRA="$TEST_TMP/missing.md" run "$SCRIPTS/release-notes.sh" v0.1.0 "" "$TEST_TMP/notes.md"
	[ "$status" -ne 0 ]
	[[ "$output" == *"neither an executable nor a file"* ]]
}
