"""Verify EC2 replacement, ALB readiness, and the public HTTPS health endpoint.

Uses the AWS CLI with a read-only OIDC role. No deployment credentials or
application secrets are needed. A failed gate prevents promotion.
"""
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def aws(*args):
    return json.loads(subprocess.check_output(
        ["aws", *args, "--output", "json"], text=True
    ))


def ready(group, targets, version, refreshes):
    if not group or group["DesiredCapacity"] < group["MinSize"]:
        return False
    if refreshes and refreshes[0]["Status"] != "Successful":
        return False
    instances = group["Instances"]
    expected = group["DesiredCapacity"]
    healthy = {
        target["Target"]["Id"] for target in targets
        if target["TargetHealth"]["State"] == "healthy"
    }
    return len(instances) >= expected and all(
        instance["LifecycleState"] == "InService"
        and instance["HealthStatus"] == "Healthy"
        and str(instance.get("LaunchTemplate", {}).get("Version")) == str(version)
        and instance["InstanceId"] in healthy
        for instance in instances
    )


def main():
    with open(sys.argv[1], encoding="utf-8") as stream:
        outputs = {key: item["value"] for key, item in json.load(stream).items()}
    url = os.environ["APPLICATION_URL"]
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username:
        raise ValueError("APPLICATION_URL must be a public HTTPS readiness URL")
    # The test certificate is self-signed, so HTTPS certificate validation is
    # intentionally omitted for this non-production rollout probe.
    tls_context = ssl._create_unverified_context()
    deadline = time.monotonic() + 1800
    consecutive = 0
    while time.monotonic() < deadline:
        groups = aws("autoscaling", "describe-auto-scaling-groups",
                     "--auto-scaling-group-names", outputs["autoscaling_group_name"])
        refreshes = aws("autoscaling", "describe-instance-refreshes",
                        "--auto-scaling-group-name", outputs["autoscaling_group_name"],
                        "--max-records", "1")["InstanceRefreshes"]
        if refreshes and refreshes[0]["Status"] in {
            "Failed", "Cancelled", "RollbackFailed", "RollbackSuccessful"
        }:
            raise RuntimeError("Instance refresh failed or rolled back: " + refreshes[0]["Status"])
        targets = aws("elbv2", "describe-target-health",
                      "--target-group-arn", outputs["target_group_arn"])["TargetHealthDescriptions"]
        group = next(iter(groups["AutoScalingGroups"]), None)
        infrastructure_ready = ready(group, targets, outputs["launch_template_version"], refreshes)
        app_ready = False
        if infrastructure_ready:
            try:
                with urllib.request.urlopen(url, timeout=10, context=tls_context) as response:
                    app_ready = response.status == 200 and response.url == url
            except (urllib.error.URLError, TimeoutError):
                pass
        consecutive = consecutive + 1 if infrastructure_ready and app_ready else 0
        if consecutive >= 3:
            print("Rollout complete: expected image version, healthy targets and HTTPS readiness verified.")
            return
        print("Waiting for stable rollout and readiness...", flush=True)
        time.sleep(15)
    raise TimeoutError("Rollout failed to become healthy within 30 minutes")


if __name__ == "__main__":
    main()
