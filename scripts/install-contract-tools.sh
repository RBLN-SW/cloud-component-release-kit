#!/usr/bin/env bash
# The same pinned versions are used by the legacy release jobs.
set -euo pipefail
bin="$HOME/.local/bin"
mkdir -p "$bin"
curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o "$bin/yq"
curl -fsSL "https://github.com/regclient/regclient/releases/download/${REGCTL_VERSION}/regctl-linux-amd64" -o "$bin/regctl"
chmod +x "$bin/yq" "$bin/regctl"
echo "$bin" >> "$GITHUB_PATH"
if ! command -v jq >/dev/null || ! command -v make >/dev/null; then
	sudo apt-get update && sudo apt-get install -y jq make
fi
