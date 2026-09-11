#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	# regctl image copy: log only. regctl image digest <ref>: a digest derived
	# from the image name so source and destination agree, unless
	# STUB_DIGEST_BREAK is set, in which case GA-tagged destinations differ.
	stub regctl 'if [ "$1 $2" = "image digest" ]; then
	ref=$3; name=${ref##*/}; name=${name%%:*}
	if [ -n "${STUB_DIGEST_BREAK:-}" ] && [[ "$ref" != *-rc* ]]; then echo "sha256:broken"; else echo "sha256:$name"; fi
fi'
}
teardown() { teardown_repo; }

@test "copies each image by digest and moves latest for the highest GA" {
	ga v0.4.0
	git tag -a v0.5.0 -m ga
	run "$SCRIPTS/promote-images.sh" v0.5.0-rc2 v0.5.0 harbor.example/proj docker.io/acme app sidecar
	[ "$status" -eq 0 ]
	grep -q '^regctl image copy harbor.example/proj/app:v0.5.0-rc2 docker.io/acme/app:v0.5.0$' "$STUB_LOG"
	grep -q '^regctl image copy docker.io/acme/app:v0.5.0 docker.io/acme/app:latest$' "$STUB_LOG"
	grep -q '^regctl image copy harbor.example/proj/sidecar:v0.5.0-rc2 docker.io/acme/sidecar:v0.5.0$' "$STUB_LOG"
	grep -q '^latest=true$' "$GITHUB_OUTPUT"
	grep -q '^app=sha256:app$' "$GITHUB_OUTPUT"
	grep -q '^sidecar=sha256:sidecar$' "$GITHUB_OUTPUT"
}

@test "a patch of an older minor does not move latest" {
	ga v0.4.0
	git tag -a v0.5.0 -m ga
	git tag -a v0.4.1 -m ga
	run "$SCRIPTS/promote-images.sh" v0.4.1-rc1 v0.4.1 harbor.example/proj docker.io/acme app
	[ "$status" -eq 0 ]
	! grep -q ':latest' "$STUB_LOG"
	grep -q '^latest=false$' "$GITHUB_OUTPUT"
	[[ "$output" == *"latest stays"* ]]
}

@test "a digest mismatch after the copy fails" {
	ga v0.5.0
	STUB_DIGEST_BREAK=1 run "$SCRIPTS/promote-images.sh" v0.5.0-rc1 v0.5.0 harbor.example/proj docker.io/acme app
	[ "$status" -ne 0 ]
	[[ "$output" == *"digest changed"* ]]
}

@test "at least one image is required" {
	run "$SCRIPTS/promote-images.sh" v0.5.0-rc1 v0.5.0 harbor.example/proj docker.io/acme
	[ "$status" -ne 0 ]
}
