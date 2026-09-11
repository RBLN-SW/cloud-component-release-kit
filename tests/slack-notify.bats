#!/usr/bin/env bats
load helpers

setup() {
	setup_repo
	stub curl 'echo "{\"ok\":true}"'
	unset SLACK_OAUTH_TOKEN SLACK_CHANNEL_ID
}
teardown() { teardown_repo; }

@test "without a token it prints a notice and exits 0" {
	run "$SCRIPTS/slack-notify.sh" --color good --title "t" "body"
	[ "$status" -eq 0 ]
	[[ "$output" == *"::notice::SLACK_OAUTH_TOKEN not set"* ]]
	! grep -q '^curl' "$STUB_LOG"
}

@test "with a token it posts a coloured attachment carrying title and body" {
	SLACK_OAUTH_TOKEN=x SLACK_CHANNEL_ID=C1 run "$SCRIPTS/slack-notify.sh" --color good --title ":rocket: *v1*" --link "https://x/y|run" "body text"
	[ "$status" -eq 0 ]
	grep -q 'chat.postMessage' "$STUB_LOG"
	grep -q '#36a64f' "$STUB_LOG"
	grep -q 'body text' "$STUB_LOG"
	grep -q '<https://x/y|run>' "$STUB_LOG"
}

@test "the one-argument form posts plain text" {
	SLACK_OAUTH_TOKEN=x SLACK_CHANNEL_ID=C1 run "$SCRIPTS/slack-notify.sh" "plain message"
	[ "$status" -eq 0 ]
	grep -q '"text": "plain message' "$STUB_LOG"
}

@test "a Slack error is a warning, not a failure" {
	stub curl 'echo "{\"ok\":false,\"error\":\"channel_not_found\"}"'
	SLACK_OAUTH_TOKEN=x SLACK_CHANNEL_ID=C1 run "$SCRIPTS/slack-notify.sh" "plain message"
	[ "$status" -eq 0 ]
	[[ "$output" == *"::warning::Slack rejected the message: channel_not_found"* ]]
}
