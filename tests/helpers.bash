#!/usr/bin/env bash
# Shared fixtures for the bats suites.
#
# setup_repo creates a bare "origin" and a clone with one commit on main, puts a
# stub directory first on PATH, and cds into the clone. Scripts under test run
# against that clone exactly as they would against a caller checkout in CI.

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$KIT_ROOT/scripts"
export KIT_ROOT SCRIPTS

setup_repo() {
	TEST_TMP=$(mktemp -d)
	ORIGIN="$TEST_TMP/origin.git"
	REPO="$TEST_TMP/repo"
	STUB_BIN="$TEST_TMP/bin"
	STUB_LOG="$TEST_TMP/stub.log"
	export TEST_TMP ORIGIN REPO STUB_BIN STUB_LOG
	mkdir -p "$STUB_BIN"
	: >"$STUB_LOG"
	git init -q --bare --initial-branch=main "$ORIGIN"
	git init -q --initial-branch=main "$REPO"
	git -C "$REPO" config user.name test
	git -C "$REPO" config user.email test@example.com
	git -C "$REPO" remote add origin "$ORIGIN"
	commit "chore: init" >/dev/null
	git -C "$REPO" push -q -u origin main
	export PATH="$STUB_BIN:$PATH"
	export GITHUB_REPOSITORY="acme/widget"
	export GITHUB_OUTPUT="$TEST_TMP/github_output"
	: >"$GITHUB_OUTPUT"
	unset GH_TOKEN RC_VALIDATION_ENFORCE
	cd "$REPO" || return 1
}

teardown_repo() {
	cd / && rm -rf "$TEST_TMP"
}

# commit <subject> [<file>]: add a commit to the current branch, print its sha.
commit() {
	local subject=$1 file=${2:-file-$RANDOM-$RANDOM.txt}
	echo "$subject $RANDOM" >>"$REPO/$file"
	git -C "$REPO" add -A
	git -C "$REPO" commit -q -m "$subject"
	git -C "$REPO" rev-parse HEAD
}

# cut <vX.Y.Z>: release branch + rc1 at HEAD, pushed. Mirrors what
# cut-release.sh produces, for tests of the later stages.
cut() {
	local v=$1 b="release-${1#v}"
	git -C "$REPO" branch -f "$b" HEAD
	git -C "$REPO" tag -a "$v-rc1" -m "rc1"
	git -C "$REPO" push -q origin "$b" "$v-rc1"
}

# ga <vX.Y.Z>: cut + GA tag on the same commit, pushed.
ga() {
	cut "$1"
	git -C "$REPO" tag -a "$1" -m "ga"
	git -C "$REPO" push -q origin "$1"
}

# origin_ref <ref>: commit sha of a branch/tag on origin, empty if absent.
origin_ref() {
	git --git-dir="$ORIGIN" rev-parse -q --verify "$1^{commit}" 2>/dev/null || true
}

# stub <name> <body>: executable on PATH that logs "<name> <args>" to STUB_LOG
# and then runs <body> (which may inspect $1, $2, ... and env).
stub() {
	cat >"$STUB_BIN/$1" <<EOF
#!/usr/bin/env bash
echo "$1 \$*" >>"$STUB_LOG"
$2
EOF
	chmod +x "$STUB_BIN/$1"
}
