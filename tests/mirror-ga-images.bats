#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	export HARBOR_REGISTRY=harbor.example/proj
	export GA_TAG=v1.2.3
	export DIGEST_APP=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
	export DIGEST_SIDECAR=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
	export REGISTRY_STATE="$TEST_TMP/registry"
	mkdir -p "$REGISTRY_STATE"
	printf '%s\n' "$DIGEST_APP" > "$REGISTRY_STATE/source-app"
	printf '%s\n' "$DIGEST_SIDECAR" > "$REGISTRY_STATE/source-sidecar"
	printf -v PROMOTED 'app=%s\nsidecar=%s\n' "$DIGEST_APP" "$DIGEST_SIDECAR"
	export PROMOTED
	stub regctl 'set -euo pipefail
ref=${3:?}; name=${ref##*/}; name=${name%%[@:]*}
case "$1 $2" in
"image digest")
    if [[ "$ref" == *@* ]]; then
        cat "$REGISTRY_STATE/source-$name"
    elif [[ "$ref" == *":$GA_TAG" ]]; then
        cat "$REGISTRY_STATE/ga-$name"
    else
        # Mutable RC tags deliberately no longer match the promoted digest.
        echo "sha256:changed-rc"
    fi
    ;;
"tag ls")
    [ "${FAIL_TAG_LIST:-}" != "$name" ] || exit 1
    echo "$GA_TAG-rc9"
    if [ -f "$REGISTRY_STATE/ga-$name" ]; then echo "$GA_TAG"; fi
    ;;
"image copy")
    [ "${FAIL_COPY:-}" != "$name" ] || exit 1
    digest=${ref##*@}
    if [ "${BREAK_COPY:-}" = "$name" ]; then digest=sha256:broken; fi
    printf "%s\n" "$digest" > "$REGISTRY_STATE/ga-$name"
    ;;
*) exit 1 ;;
esac'
}

teardown() { teardown_repo; }

@test "copies exact promoted digests for every image and leaves latest untouched" {
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -eq 0 ]
	grep -Fxq "regctl image copy $HARBOR_REGISTRY/app@$DIGEST_APP $HARBOR_REGISTRY/app:$GA_TAG" "$STUB_LOG"
	grep -Fxq "regctl image copy $HARBOR_REGISTRY/sidecar@$DIGEST_SIDECAR $HARBOR_REGISTRY/sidecar:$GA_TAG" "$STUB_LOG"
	[ "$(cat "$REGISTRY_STATE/ga-app")" = "$DIGEST_APP" ]
	[ "$(cat "$REGISTRY_STATE/ga-sidecar")" = "$DIGEST_SIDECAR" ]
	! grep -Eq ':latest|image (copy|digest) .*-rc' "$STUB_LOG"
}

@test "a rerun with matching GA tags does not copy again" {
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -eq 0 ]
	: > "$STUB_LOG"
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -eq 0 ]
	! grep -q '^regctl image copy ' "$STUB_LOG"
}

@test "a conflicting second image prevents all writes" {
	echo sha256:other > "$REGISTRY_STATE/ga-sidecar"
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -ne 0 ]
	[[ "$output" == *"different digest"* ]]
	! grep -q '^regctl image copy ' "$STUB_LOG"
	[ ! -f "$REGISTRY_STATE/ga-app" ]
}

@test "missing duplicate and invalid promoted digests prevent all writes" {
	local original=$PROMOTED
	for PROMOTED in "app=$DIGEST_APP" "${original}sidecar=$DIGEST_SIDECAR" "app=$DIGEST_APP"$'\nsidecar=sha256:invalid'; do
		run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
		[ "$status" -ne 0 ]
		[[ "$output" == *"invalid or missing promoted digest for sidecar"* ]]
		! grep -q '^regctl image copy ' "$STUB_LOG"
	done
}

@test "only GA tags are accepted and at least one image is required" {
	for tag in v1.2.3-rc9 dev 1.2.3; do
		run "$SCRIPTS/mirror-ga-images.sh" "$tag" app
		[ "$status" -ne 0 ]
		[[ "$output" == *"expected a GA tag"* ]]
	done
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG"
	[ "$status" -ne 0 ]
	[ ! -s "$STUB_LOG" ]
}

@test "a source digest mismatch prevents all writes" {
	echo sha256:other > "$REGISTRY_STATE/source-sidecar"
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -ne 0 ]
	[[ "$output" == *"source digest mismatch"* ]]
	! grep -q '^regctl image copy ' "$STUB_LOG"
}

@test "a missing source prevents all writes" {
	rm "$REGISTRY_STATE/source-sidecar"
	run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -ne 0 ]
	! grep -q '^regctl image copy ' "$STUB_LOG"
}

@test "registry failure is not treated as an absent GA tag" {
	FAIL_TAG_LIST=sidecar run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -ne 0 ]
	! grep -q '^regctl image copy ' "$STUB_LOG"
}

@test "a failed copy stops the job" {
	FAIL_COPY=app run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -ne 0 ]
	[ "$(grep -c '^regctl image copy ' "$STUB_LOG")" -eq 1 ]
	[ ! -f "$REGISTRY_STATE/ga-app" ]
	[ ! -f "$REGISTRY_STATE/ga-sidecar" ]
}

@test "a digest mismatch after copying fails the job" {
	BREAK_COPY=app run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app sidecar
	[ "$status" -ne 0 ]
	[[ "$output" == *"digest changed while copying"* ]]
	[ "$(grep -c '^regctl image copy ' "$STUB_LOG")" -eq 1 ]
}

@test "a registry with a trailing slash is normalized" {
	HARBOR_REGISTRY="$HARBOR_REGISTRY/" run "$SCRIPTS/mirror-ga-images.sh" "$GA_TAG" app
	[ "$status" -eq 0 ]
	grep -Fxq "regctl image copy $HARBOR_REGISTRY/app@$DIGEST_APP $HARBOR_REGISTRY/app:$GA_TAG" "$STUB_LOG"
}
