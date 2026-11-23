#!/usr/bin/env python3
"""GitHub Actions adapter for the repository-owned Piper artifact interface."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

MANIFEST = ".piper/release.yaml"
DIGEST = re.compile(r"sha256:[a-f0-9]{64}")


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temp.replace(path)


def out(*args):
    return subprocess.check_output(args, text=True).strip()


def declared():
    manifest = json.loads(out("yq", "-o=json", ".", MANIFEST))
    if manifest["schemaVersion"] != 1 or manifest["makeTarget"] != "release-artifact":
        raise ValueError("unsupported release contract")
    return manifest["artifacts"]


def ref_for(image):
    return f"{image['registry']}/{image['repository']}:{image['tag']}"


def checked_digest(reference):
    value = out("regctl", "image", "digest", reference)
    if not DIGEST.fullmatch(value):
        raise ValueError(f"invalid registry digest for {reference}")
    return value


def registry_digest_if_present(reference):
    p = subprocess.run(["regctl", "image", "digest", reference], text=True, capture_output=True)
    if p.returncode == 0 and DIGEST.fullmatch(p.stdout.strip()):
        return p.stdout.strip()
    if p.returncode and re.search(r'(?i)(not found|manifest unknown|404)', p.stderr):
        return None
    raise RuntimeError(f"cannot establish registry state of {reference}: {p.stderr.strip()}")


def call_artifact(spec, plan_path, result_path):
    subprocess.run(["make", "release-artifact", f"ARTIFACT_NAME={spec['name']}",
                    f"ARTIFACT_KIND={spec['kind']}", f"RELEASE_INPUT={Path(plan_path).resolve()}",
                    f"RELEASE_RESULT={Path(result_path).resolve()}"], check=True)
    result = read(result_path)
    if (result["schemaVersion"], result["name"], result["kind"]) != (1, spec["name"], spec["kind"]):
        raise ValueError("artifact result does not match requested artifact")
    return result["output"]


def rc_images(plan_path):
    target = os.environ["HARBOR_REGISTRY"]
    version = os.environ["GITHUB_REF_NAME"]
    plan = dict(schemaVersion=1, phase="rc", version=version, sourceSha=out("git", "rev-parse", "HEAD"),
                targetRegistry=target, components={})
    specs = [a for a in declared() if a["kind"] == "image"]
    if sorted(a["repository"] for a in specs) != sorted(os.environ["IMAGES"].split()):
        raise ValueError("workflow images differ from .piper/release.yaml")
    previous = Path(plan_path)
    if previous.is_file():
        saved = read(previous)
        if any(plan[k] != saved.get(k) for k in ("version", "sourceSha", "targetRegistry", "phase", "schemaVersion")):
            raise ValueError("saved image receipts belong to a different release")
        plan["components"] = saved["components"]
    write(plan_path, plan)
    with tempfile.TemporaryDirectory() as tmp:
        for spec in specs:
            reference = f"{target}/{spec['repository']}:{version}"
            existing = registry_digest_if_present(reference)
            receipt = plan["components"].get(spec["name"])
            if receipt is not None:
                if ref_for(receipt) != reference or not existing or receipt["digest"] != existing:
                    raise ValueError(f"recorded RC image changed: {reference}")
                continue
            if existing:
                raise ValueError(f"{reference} is already published; refusing to overwrite an RC")
            result = call_artifact(spec, plan_path, Path(tmp) / "image.json")
            if result["type"] != "registry" or result["ref"] != reference or result["digest"] != checked_digest(reference):
                raise ValueError(f"image receipt does not match {reference}")
            registry, repo = (target + "/" + spec["repository"]).split("/", 1)
            plan["components"][spec["name"]] = dict(registry=registry, repository=repo,
                                                      tag=version, digest=result["digest"])
            write(plan_path, plan)


def ga_input(rc_path, result):
    plan = read(rc_path)
    version = os.environ["GITHUB_REF_NAME"]
    if (plan["schemaVersion"] != 1 or plan["phase"] != "rc" or plan["version"] != os.environ["LAST_RC"]
            or plan["version"].split("-rc")[0] != version or plan["sourceSha"] != out("git", "rev-parse", "HEAD")):
        raise ValueError("release input is not the selected RC at the GA source SHA")
    target = os.environ["DOCKERHUB_REGISTRY"]
    specs = declared()
    for spec in (a for a in specs if a["kind"] == "image"):
        image = plan["components"][spec["name"]]
        expected = f"{os.environ['HARBOR_REGISTRY']}/{spec['repository']}:{plan['version']}"
        if ref_for(image) != expected or not DIGEST.fullmatch(image["digest"]):
            raise ValueError(f"invalid source image for {spec['name']}")
        dest = f"{target}/{spec['repository']}:{version}"
        existing = registry_digest_if_present(dest)
        if existing and existing != image["digest"]:
            raise ValueError(f"public GA tag already points to another digest: {dest}")
    if any(a["kind"] == "helm-chart" for a in specs):
        chart = plan["artifacts"]["chart"]
        if checked_digest(chart["ref"]) != chart["digest"]:
            raise ValueError("RC chart tag no longer matches the validated chart")
        subprocess.run(["make", "release-input", "RELEASE_PHASE=ga", f"RELEASE_INPUT={rc_path}",
                        f"VERSION={version}", f"PUBLIC_REGISTRY={target}", f"RELEASE_RESULT={result}"], check=True)
    else:
        plan.update(phase="ga", version=version, promotedFrom=plan["version"], targetRegistry=target)
        for spec in (a for a in specs if a["kind"] == "image"):
            image = plan["components"][spec["name"]]
            image["registry"], image["repository"] = (target + "/" + spec["repository"]).split("/", 1)
            image["tag"] = version
        write(result, plan)


def chart_files(path):
    with tarfile.open(path, "r:gz") as archive:
        return {m.name: archive.extractfile(m).read() for m in archive if m.isfile()}


def publish_chart(plan_path):
    plan = read(plan_path)
    spec, = (a for a in declared() if a["kind"] == "helm-chart")
    target = plan["targetRegistry"] + "/" + spec["repository"]
    reference = target + ":" + plan["version"].removeprefix("v")
    result = call_artifact(spec, plan_path, Path(plan_path).parent / "chart-result.json")
    if result["type"] != "file":
        raise ValueError("expected a packaged chart file")
    package = Path(result["path"])
    # A retry may reuse exactly the same OCI layer. Never replace a published tag.
    digest = registry_digest_if_present(reference)
    if digest is None:
        subprocess.run(["helm", "push", package, "oci://" + plan["targetRegistry"]], check=True)
        digest = checked_digest(reference)
    manifest = json.loads(out("regctl", "manifest", "get", target + "@" + digest, "--format", "raw-body"))
    layer, = (x for x in manifest["layers"] if x["mediaType"] == "application/vnd.cncf.helm.chart.content.v1.tar+gzip")
    if layer["digest"] != "sha256:" + hashlib.sha256(package.read_bytes()).hexdigest():
        # Helm archive timestamps can differ on retry. Verify every packaged file,
        # then attach the original registry bytes to GitHub.
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["helm", "pull", "oci://" + target + "@" + digest, "--destination", tmp], check=True)
            original, = Path(tmp).glob("*.tgz")
            if (hashlib.sha256(original.read_bytes()).hexdigest() != layer["digest"].split(":")[1]
                    or chart_files(original) != chart_files(package)):
                raise ValueError(f"OCI content differs from the packaged chart: {reference}")
            shutil.copyfile(original, package)
    plan["artifacts"] = {"chart": {"ref": reference, "digest": digest}}
    write(plan_path, plan)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for command, fields in {"rc-images": ["result"], "ga-input": ["input", "result"],
                            "publish-chart": ["input"]}.items():
        p = sub.add_parser(command)
        for field in fields:
            p.add_argument(field)
    args = parser.parse_args()
    if args.command == "rc-images":
        rc_images(args.result)
    elif args.command == "ga-input":
        ga_input(args.input, args.result)
    else:
        publish_chart(args.input)
