#!/usr/bin/env python3
"""Select an available concrete iPhone simulator for GitHub Actions."""

import os
import re
import subprocess
import sys


def run_and_print(command: list[str], label: str) -> str:
    print(f"::group::{label}", flush=True)
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    print("::endgroup::", flush=True)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(command)} exited with status {result.returncode}")
    return result.stdout


def main() -> int:
    try:
        run_and_print(["xcodebuild", "-version"], "Xcode version")
        output = run_and_print(
            [
                "xcodebuild",
                "-showdestinations",
                "-project",
                "Leafy.xcodeproj",
                "-scheme",
                "Leafy",
            ],
            "Available Leafy destinations",
        )
    except (OSError, RuntimeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    destinations = []
    for match in re.finditer(r"\{([^}]+)\}", output):
        fields = {}
        for part in match.group(1).split(","):
            if ":" not in part:
                continue
            key, value = part.split(":", 1)
            fields[key.strip()] = value.strip()
        destination_id = fields.get("id", "")
        if (
            fields.get("platform") == "iOS Simulator"
            and fields.get("name", "").startswith("iPhone")
            and destination_id
            and "placeholder" not in destination_id
            and "error" not in fields
        ):
            destinations.append(fields)

    preferences = (
        "iPhone 17 Pro",
        "iPhone 17",
        "iPhone 16 Pro",
        "iPhone 16",
        "iPhone 16 Plus",
        "iPhone 15 Pro",
        "iPhone 15",
    )
    chosen = next(
        (
            destination
            for preferred_name in preferences
            for destination in destinations
            if destination["name"] == preferred_name
        ),
        destinations[0] if destinations else None,
    )
    if chosen is None:
        print(
            "::error::No available concrete iPhone Simulator destination was found. "
            "See the Xcode version and complete destination list above.",
            file=sys.stderr,
        )
        return 1

    github_env = os.environ.get("GITHUB_ENV")
    if not github_env:
        print("::error::GITHUB_ENV is not set", file=sys.stderr)
        return 1

    destination = f"platform=iOS Simulator,id={chosen['id']}"
    print(
        f"Using destination: {destination} "
        f"({chosen['name']}, OS={chosen.get('OS', 'unknown')})"
    )
    with open(github_env, "a", encoding="utf-8") as handle:
        handle.write(f"IOS_TEST_DESTINATION={destination}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
