#!/usr/bin/env bash
# Keep GA image tags in Harbor using the exact digests promoted to Docker Hub.
# Required env: HARBOR_REGISTRY, PROMOTED (one image=sha256:... line per image).
# Does not move Harbor's latest tag. Existing GA tags must have the same digest.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage="usage: mirror-ga-images.sh <vX.Y.Z> <image>..."
tag=${1:?$usage}
shift
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "expected a GA tag, got $tag"
[ $# -gt 0 ] || fail "$usage"
: "${HARBOR_REGISTRY:?}" "${PROMOTED:?}"
registry=${HARBOR_REGISTRY%/}
images=("$@")
digests=()
present=()

# Validate every source and destination before writing any GA tag.
for image in "${images[@]}"; do
	digest=$(awk -F= -v image="$image" '$1 == image {print $2}' <<< "$PROMOTED")
	[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid or missing promoted digest for $image"

	source="$registry/$image@$digest"
	actual=$(regctl image digest "$source")
	[ "$actual" = "$digest" ] || fail "source digest mismatch for $source: $actual"

	# Listing tags distinguishes an absent tag from authentication/network errors.
	tags=$(regctl tag ls "$registry/$image")
	exists=false
	if grep -Fxq -- "$tag" <<< "$tags"; then
		actual=$(regctl image digest "$registry/$image:$tag")
		[ "$actual" = "$digest" ] || fail "$registry/$image:$tag already points to a different digest"
		exists=true
	fi
	digests+=("$digest")
	present+=("$exists")
done

for i in "${!images[@]}"; do
	target="$registry/${images[$i]}:$tag"
	if [ "${present[$i]}" = false ]; then
		regctl image copy "$registry/${images[$i]}@${digests[$i]}" "$target"
	fi
	actual=$(regctl image digest "$target")
	[ "$actual" = "${digests[$i]}" ] || fail "digest changed while copying $target: $actual"
	note "$target@$actual"
done
