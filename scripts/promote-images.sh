#!/usr/bin/env bash
# Promote the newest rc's images to the GA registry by digest, without a rebuild.
#
#   scripts/promote-images.sh <last_rc> <ga_tag> <src_registry> <dst_registry> <image>...
#
# For every image: copy <src_registry>/<image>:<last_rc> to
# <dst_registry>/<image>:<ga_tag> with regctl, verify the digest did not change,
# and when <ga_tag> is the highest GA tag known locally also tag it latest. A
# patch of an older minor (0.4.1 after 0.5.0 shipped) must not move latest back.
#
# Requires regctl logged in to both registries and the repository's tags
# fetched. Writes latest=<true|false> and a multi-line digests block
# (<image>=sha256:...) to $GITHUB_OUTPUT when set.

set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage="usage: promote-images.sh <last_rc> <ga_tag> <src_registry> <dst_registry> <image>..."
last_rc=${1:?$usage}
ga_tag=${2:?$usage}
src=${3:?$usage}
dst=${4:?$usage}
shift 4
[ $# -gt 0 ] || fail "$usage"

highest=$(last_ga_tag)
move_latest=false
if [ "$highest" = "$ga_tag" ]; then
	move_latest=true
else
	note "$ga_tag is below the highest GA $highest; latest stays"
fi

digests=""
for img in "$@"; do
	from="$src/$img:$last_rc"
	to="$dst/$img:$ga_tag"
	regctl image copy "$from" "$to"
	s=$(regctl image digest "$from")
	d=$(regctl image digest "$to")
	[ "$s" = "$d" ] || fail "digest changed while copying $img: $s -> $d"
	if [ "$move_latest" = true ]; then
		regctl image copy "$to" "$dst/$img:latest"
	fi
	note "$img: $to@$d (= $from)"
	digests="$digests$img=$d"$'\n'
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "latest=$move_latest"
		echo "digests<<PROMOTE_EOF"
		printf '%s' "$digests"
		echo "PROMOTE_EOF"
	} >>"$GITHUB_OUTPUT"
fi
