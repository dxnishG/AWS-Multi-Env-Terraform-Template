import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "verify_rollout", Path(__file__).with_name("verify_rollout.py")
)
rollout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rollout)


class RolloutGateTests(unittest.TestCase):
    def setUp(self):
        self.group = {
            "DesiredCapacity": 2, "MinSize": 2,
            "Instances": [
                {"InstanceId": name, "LifecycleState": "InService",
                 "HealthStatus": "Healthy", "LaunchTemplate": {"Version": "7"}}
                for name in ["i-one", "i-two"]
            ],
        }
        self.targets = [
            {"Target": {"Id": name}, "TargetHealth": {"State": "healthy"}}
            for name in ["i-one", "i-two"]
        ]

    def test_accepts_complete_rollout(self):
        self.assertTrue(rollout.ready(self.group, self.targets, "7", []))

    def test_rejects_old_image_even_with_healthy_targets(self):
        self.group["Instances"][0]["LaunchTemplate"]["Version"] = "6"
        self.assertFalse(rollout.ready(self.group, self.targets, "7", []))

    def test_rejects_missing_target(self):
        self.assertFalse(rollout.ready(self.group, self.targets[:1], "7", []))

    def test_rejects_in_progress_or_rolled_back_refresh(self):
        for status in ["InProgress", "RollbackSuccessful", "Failed"]:
            self.assertFalse(rollout.ready(self.group, self.targets, "7", [{"Status": status}]))

    def test_rejects_missing_capacity(self):
        self.group["Instances"].pop()
        self.assertFalse(rollout.ready(self.group, self.targets, "7", []))


if __name__ == "__main__":
    unittest.main()
