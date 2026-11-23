# cloud-component-release-kit

Reusable GitHub Actions workflows and scripts for releasing RBLN-SW cloud components.

- `cut-release` creates `release-X.Y.Z` and tags `vX.Y.Z-rc1`.
- `vX.Y.Z-rcN` tags publish images (and an optional Helm chart) to the staging registry.
- Fixes land on `main` and are backported with the `backport release-X.Y.Z` label.
- `tag-release ga` tags `vX.Y.Z`; the rc images are promoted by digest to the public registry.

## Layout

```
.github/workflows/   reusable workflows (workflow_call): cut-release, tag-release, backport, release-policy, release
                     mirror-ga-images (optional internal Harbor copy after release)
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

## Harbor GA image copies

The optional `ga-harbor-images` job in the release caller template invokes
`mirror-ga-images.yaml` after the public `release` workflow succeeds. It uses
that workflow's `digests` output to add matching `vX.Y.Z` tags in Harbor without
rebuilding or re-resolving RC tags. Harbor's `latest` tag is unchanged.

The job uses `CLOUD_COMPONENT_HARBOR_REGISTRY`, the existing Harbor credentials
and the internal runner. A matching GA tag makes a retry a no-op; a conflicting
tag is never overwritten. Setup, login and copy failures produce a warning
annotation and job summary, without failing the overall caller workflow.
The public release, chart, notes and notification have already completed.

The reusable workflow exposes `outputs.outcome` (`success` or `warning`) so
caller summaries can report an incomplete copy even though the job succeeded.
Job-level failures, including timeouts, are also tolerated; if no output is
available for an attempted copy, summaries should treat it as a warning.
Inspect the Harbor job's logs before retrying it. Docker Hub release failures
remain fatal; only this optional Harbor job tolerates failures.

Publish the new workflow and script under `v1` before merging caller jobs that
reference them. Existing callers without this job keep their current behavior.

## Piper artifact contract during migration

Consumers opt in with `artifact_contract: true` and commit a schema-version-1
`.piper/release.yaml` alongside their Makefile. Deploy this reusable workflow
on the version referenced by consumers before merging those workflow changes.
Existing callers without the option keep their current release path.

The runner checks out the release commit and invokes:

```sh
make release-artifact ARTIFACT_KIND=image ARTIFACT_NAME=devicePlugin \
  RELEASE_INPUT=/work/release-input.json RELEASE_RESULT=/work/result.json
```

The input contains `schemaVersion`, `sourceSha`, `phase`, `version`,
`targetRegistry` (host/project) and `components`. Image repository names in
the declaration are relative to that registry project. The result identifies
`name` and `kind`; `output` is either a file path or a registry ref and
its digest. An image build pushes only to the RC destination. GA copies the
digest recorded in the RC release asset. The adapter cross-checks the declared
images against the existing workflow input before building.

Image-only projects omit chart inputs. For a product chart the repository's
`make release-input` freezes dependencies at RC and translates them to verified
public coordinates at GA. Both the chart package and the frozen input are
attached to the GitHub release. Keep the tag workflow, validation and GA
mirroring active until Piper takes over publication.
