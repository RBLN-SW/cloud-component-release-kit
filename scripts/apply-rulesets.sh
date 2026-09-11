#!/usr/bin/env bash
# Apply the release rulesets in rulesets/ to a repository.
#
#   scripts/apply-rulesets.sh --team <team-slug> --app-id <github-app-id> \
#       [--repo <owner/repo>] [--checks "<ctx>[@<integration_id>],..."] [--dry-run]
#
# Rulesets are kept as JSON so the same protection can be reviewed in a PR and
# replayed on every repository. Placeholders are resolved here:
#   __TEAM_ID__   the team slug becomes its numeric id
#   __APP_ID__    the GitHub App's id (Settings > Developer settings > GitHub
#                 Apps), not the installation id
#   required_status_checks   filled from --checks. Each entry is a status-check
#                 context, optionally "@<integration_id>"; the default
#                 integration is GitHub Actions (15368). Reusable-workflow jobs
#                 report as "<caller job id> / <called job name>". The
#                 release-branches ruleset always requires
#                 "release-policy / release-policy". A ruleset left with no
#                 checks drops the required_status_checks rule.
#
# An existing ruleset with the same name is updated in place (PUT), otherwise
# it is created (POST). If the API rejects the `required_reviewers` parameter,
# the ruleset is applied again without it and a warning tells you to require
# the team via CODEOWNERS on the release branch instead.
#
# Requires: gh authenticated with admin rights on the repository.

set -euo pipefail
rulesets_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../rulesets" && pwd)"

usage="usage: apply-rulesets.sh --team <slug> --app-id <id> [--repo owner/repo] [--checks ctx[@id],...] [--dry-run]"
team="" app_id="" repo="" checks="" dry_run=0
while [ $# -gt 0 ]; do
	case $1 in
	--team) team=$2; shift 2 ;;
	--app-id) app_id=$2; shift 2 ;;
	--repo) repo=$2; shift 2 ;;
	--checks) checks=$2; shift 2 ;;
	--dry-run) dry_run=1; shift ;;
	*) echo "unknown argument: $1" >&2; echo "$usage" >&2; exit 2 ;;
	esac
done
if [ -z "$team" ] || [ -z "$app_id" ]; then echo "$usage" >&2; exit 2; fi
[ -n "$repo" ] || repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
org=${repo%%/*}

team_id=$(gh api "orgs/$org/teams/$team" --jq .id) || { echo "team $org/$team not found" >&2; exit 1; }
[ -n "$team_id" ] || { echo "team $org/$team not found" >&2; exit 1; }
echo "repo=$repo team=$team (id $team_id) app_id=$app_id checks=${checks:-<none>}"

existing=$(gh api "repos/$repo/rulesets" --jq '.[] | "\(.name) \(.id)"' 2>/dev/null || true)

# checks_json [<extra ctx>...]: JSON array for required_status_checks, built
# from --checks plus the extras, de-duplicated.
checks_json() {
	{
		for x in "$@"; do echo "$x"; done
		tr ',' '\n' <<<"$checks"
	} | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | sort -u | jq -R -s '
		split("\n") | map(select(length > 0)) |
		map(if test("@[0-9]+$") then {context: sub("@[0-9]+$"; ""), integration_id: (capture("@(?<id>[0-9]+)$").id | tonumber)}
		    else {context: ., integration_id: 15368} end)'
}

apply() { # <name> <json>
	local name=$1 body=$2 id method path
	id=$(awk -v n="$name" '$1 == n { print $2 }' <<<"$existing")
	if [ -n "$id" ]; then method=PUT; path="repos/$repo/rulesets/$id"; else method=POST; path="repos/$repo/rulesets"; fi
	if [ "$dry_run" = 1 ]; then
		echo "--- $method $path"; jq . <<<"$body"; return 0
	fi
	gh api -X "$method" "$path" --input - <<<"$body" >/dev/null
}

for f in "$rulesets_dir"/*.json; do
	name=$(jq -r .name "$f")
	body=$(sed -e "s/\"__TEAM_ID__\"/$team_id/g" -e "s/\"__APP_ID__\"/$app_id/g" "$f")
	if jq -e '.rules[] | select(.type == "required_status_checks")' <<<"$body" >/dev/null; then
		if [ "$name" = release-branches ]; then
			cj=$(checks_json "release-policy / release-policy")
		else
			cj=$(checks_json)
		fi
		body=$(jq --argjson checks "$cj" '
			if ($checks | length) == 0 then .rules |= map(select(.type != "required_status_checks"))
			else (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks) = $checks end' <<<"$body")
	fi
	if apply "$name" "$body"; then
		echo "ok    $name"
		continue
	fi
	if jq -e '.rules[] | select(.type == "pull_request") | .parameters.required_reviewers' <<<"$body" >/dev/null 2>&1; then
		echo "warn  $name: retrying without pull_request.required_reviewers"
		body=$(jq '(.rules[] | select(.type == "pull_request") | .parameters) |= del(.required_reviewers)' <<<"$body")
		if apply "$name" "$body"; then
			echo "ok    $name (without required_reviewers). Add '* @$org/$team' to .github/CODEOWNERS on release branches and set require_code_owner_review, or upgrade the API."
			continue
		fi
	fi
	echo "FAIL  $name" >&2
	exit 1
done
