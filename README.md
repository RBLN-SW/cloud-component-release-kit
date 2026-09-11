# cloud-component-release-kit

Reusable GitHub Actions workflows and scripts for releasing RBLN-SW cloud components.

- `cut-release` creates `release-X.Y.Z` and tags `vX.Y.Z-rc1`.
- `vX.Y.Z-rcN` tags publish images (and an optional Helm chart) to the staging registry.
- Fixes land on `main` and are backported with the `backport release-X.Y.Z` label.
- `tag-release ga` tags `vX.Y.Z`; the rc images are promoted by digest to the public registry.

## Layout

```
.github/workflows/   reusable workflows (workflow_call): cut-release, tag-release, backport, release-policy, release
scripts/             shell scripts behind the workflows
rulesets/            branch and tag protection, applied with scripts/apply-rulesets.sh
templates/workflows/ caller stubs to copy into a repository's .github/workflows/
tests/               bats tests for the scripts
```

## Using it in a repository

1. Copy `templates/workflows/*.yaml` into `.github/workflows/` and fill in the `with:` values.
2. Provide a `make build-image IMAGE_NAME=<registry>/<image> VERSION=<tag> BUILD_MULTI_PLATFORM=true PUSH_ON_BUILD=true` target.
3. Set the `CLOUD_COMPONENT_*` variables and secrets referenced in the workflow headers.
4. Run `scripts/setup-labels.sh` and `scripts/apply-rulesets.sh` for the repository.

## Development

```
bats tests
shellcheck -x -P SCRIPTDIR scripts/*.sh tests/helpers.bash
actionlint .github/workflows/*.yaml templates/workflows/*.yaml
```

Consumers pin the moving major tag `v1`.
