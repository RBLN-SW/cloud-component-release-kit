#!/usr/bin/env bash
# Generate the release notes draft for a GA (or rc) tag.
#
#   scripts/release-notes.sh <tag> [<previous GA tag>] [<output file>]
#
# The range is <previous GA>..<tag>. Because release branches carry
# cherry-picks of main commits, the raw log could list a fix twice; two kinds
# of commits are dropped:
#   - a backport (a commit with a "(cherry picked from commit <sha>)" trailer)
#     whose origin is itself in the range: the origin is listed instead. On a
#     patch branch the origin is NOT in the range (main is not an ancestor past
#     the cut), so the backport stays and is the only record of the fix.
#   - a main commit whose sha appears as a trailer in the previous GA's own
#     backports: that fix already shipped in the previous release.
# Commits are grouped by Conventional Commit type. If RELEASE_NOTES_EXTRA names
# a file, its content is appended after Known Issues (repositories that pin
# other images, like the operator, put their component table there).

set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tag=${1:?usage: release-notes.sh <tag> [<prev GA tag>] [<out>]}
prev=${2:-}
out=${3:-release_notes.md}
repo=$(repo_slug)
[ -n "$repo" ] || fail "cannot determine owner/repo: set GITHUB_REPOSITORY or authenticate gh"

trailer_shas() { # <range> -> origin shas named in cherry-pick trailers
	git log --format=%B "$1" | sed -n 's/^(cherry picked from commit \([0-9a-f]\{40\}\))$/\1/p' | sort -u
}

if [ -n "$prev" ]; then
	range="$prev..$tag"
	base=$(git merge-base "$prev" "$tag")
	shipped=$(trailer_shas "$base..$prev")
else
	range=$tag
	shipped=""
fi

in_range=$(git rev-list --no-merges "$range")
commits=$(mktemp)
trap 'rm -f "$commits"' EXIT
for c in $in_range; do
	origins=$(git log -1 --format=%B "$c" | sed -n 's/^(cherry picked from commit \([0-9a-f]\{40\}\))$/\1/p')
	listed_via_origin=0
	for o in $origins; do
		grep -qx -- "$o" <<<"$in_range" && listed_via_origin=1
	done
	[ "$listed_via_origin" = 1 ] && continue # a backport whose origin is listed
	grep -qx -- "$c" <<<"$shipped" && continue # already shipped via the previous GA
	git log -1 --format="%s ([%h](https://github.com/$repo/commit/%H))" "$c" |
		sed -E "s|\(#([0-9]+)\)|([#\1](https://github.com/$repo/pull/\1))|g" >>"$commits"
done

get() { grep -E "^$1(\(.*\))?!?:" "$commits" || true; }
bullets() { sed 's/^/- /'; }
breaking=$(grep -E '^[a-z]+(\(.*\))?!:' "$commits" || true)
feats=$(get feat)
fixes=$(get fix)
improvements=$(for t in docs refactor perf style build chore test ci; do get "$t"; done)

{
	echo "# Release Notes"
	echo
	if [ -n "$breaking" ]; then
		echo "## ⚠ Breaking Changes"
		bullets <<<"$breaking"
		echo
		echo "> Review the documentation at this tag ([$tag](https://github.com/$repo/tree/$tag)) before upgrading."
		echo
	fi
	echo "## New Features"
	if [ -n "$feats" ]; then bullets <<<"$feats"; else echo "- None"; fi
	echo
	echo "## Improvements"
	if [ -n "$improvements" ]; then bullets <<<"$improvements"; else echo "- None"; fi
	echo
	echo "## Fixed Issues"
	if [ -n "$fixes" ]; then bullets <<<"$fixes"; else echo "- None"; fi
	echo
	echo "## Known Issues"
	echo "- TBD"
	echo
	if [ -n "${RELEASE_NOTES_EXTRA:-}" ] && [ -f "$RELEASE_NOTES_EXTRA" ]; then
		cat "$RELEASE_NOTES_EXTRA"
		echo
	fi
	if [ -n "$prev" ]; then
		echo "_Changes since $prev. Generated for $tag._"
	else
		echo "_Generated for $tag._"
	fi
} >"$out"

echo "wrote $out ($(grep -c '^- ' "$out") bullet(s), range ${prev:-<start>}..$tag)"
