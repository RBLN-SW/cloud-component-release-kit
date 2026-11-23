"""Registry-independent tests for release receipts and resuming interrupted jobs."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "contract", Path(__file__).resolve().parents[1] / "scripts/artifact-contract.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ReceiptTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "rc.json"
        self.spec = {"name": "plugin", "kind": "image", "repository": "plugin"}
        self.digest = "sha256:" + "2" * 64
        self.sha = "1" * 40
        self.tag = "v0.6.0-rc1"
        self.image = dict(registry="harbor.test", repository="team/plugin",
                          tag=self.tag, digest=self.digest)
        self.plan = dict(schemaVersion=1, sourceSha=self.sha, phase="rc", version=self.tag,
                         targetRegistry="harbor.test/team", components={"plugin": self.image})
        contract.write(self.path, self.plan)
        for context in (patch.object(contract, "declared", return_value=[self.spec]),
                        patch.object(contract, "out", return_value=self.sha),
                        patch.dict(os.environ, {"HARBOR_REGISTRY": "harbor.test/team", "IMAGES": "plugin",
                                                "GITHUB_REF_NAME": self.tag})):
            context.start()
            self.addCleanup(context.stop)

    def test_retry_reuses_only_recorded_registry_digest(self):
        with patch.object(contract, "registry_digest_if_present", return_value=self.digest), \
             patch.object(contract, "call_artifact") as build:
            contract.rc_images(self.path)
            build.assert_not_called()
        with patch.object(contract, "registry_digest_if_present", return_value="sha256:" + "3" * 64):
            with self.assertRaisesRegex(ValueError, "recorded RC image changed"):
                contract.rc_images(self.path)

    def test_preexisting_tag_without_receipt_is_never_overwritten(self):
        self.path.unlink()
        with patch.object(contract, "registry_digest_if_present", return_value=self.digest), \
             patch.object(contract, "call_artifact") as build:
            with self.assertRaisesRegex(ValueError, "already published"):
                contract.rc_images(self.path)
            build.assert_not_called()

    def test_ga_uses_exact_source_and_refuses_conflicting_public_tag(self):
        dest = self.path.with_name("ga.json")
        env = {"GITHUB_REF_NAME": "v0.6.0", "LAST_RC": self.tag, "DOCKERHUB_REGISTRY": "docker.io/team"}
        with patch.dict(os.environ, env), patch.object(contract, "registry_digest_if_present") as remote:
            remote.return_value = None
            contract.ga_input(self.path, dest)
            ga = contract.read(dest)
            self.assertEqual(ga["promotedFrom"], self.tag)
            self.assertEqual(ga["components"]["plugin"], {**self.image, "registry": "docker.io", "tag": "v0.6.0"})
            remote.return_value = "sha256:" + "9" * 64
            with self.assertRaisesRegex(ValueError, "another digest"):
                contract.ga_input(self.path, dest)
            contract.write(self.path, {**self.plan, "sourceSha": "4" * 40})
            with self.assertRaisesRegex(ValueError, "source SHA"):
                contract.ga_input(self.path, dest)
