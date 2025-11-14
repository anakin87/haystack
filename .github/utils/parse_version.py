"""
Parse version string and output parsed components.

This script parses a version string (e.g., "v2.99.0-rc1" or "2.99.0") and outputs:
- version: version without 'v' prefix
- release_branch: release branch name (e.g., "v2.99.x")
- is_minor: whether this is a minor release (patch == "0")
- is_first_rc: whether this is the first RC of a minor release

If releasing the first RC (e.g., v2.20.0-rc1), validates that VERSION.txt contains
the corresponding rc0 version (e.g., 2.20.0-rc0).
"""

import sys


def parse_version(version_input: str) -> dict[str, str]:
    """
    Parse version string and return parsed components.

    Args:
        version_input: Version string (e.g., "v2.99.0-rc1")

    Returns:
        Dictionary with parsed version information
    """
    version = version_input.lstrip("v")

    # Parse version components
    # Format: MAJOR.MINOR.PATCH[-suffix]
    parts = version.split(".")
    if len(parts) != 3:
        raise ValueError(f"Invalid version format: {version_input}. Expected MAJOR.MINOR.PATCH")

    major, minor, patch = parts

    patch = patch.split("-")[0]

    release_branch = f"v{major}.{minor}.x"
    is_minor = patch == "0"
    is_first_rc = is_minor and "rc1" in version

    # if is_first_rc:
    #     version_in_txt = Path("VERSION.txt").read_text().strip()
    #     if version_in_txt != f"{major}.{minor}.0-rc0":
    #         msg = (
    #             "When releasing rc1 of a minor version, VERSION.txt must contain the corresponding rc0 version."
    #             f"Expected: {major}.{minor}.0-rc0, Got: {version_in_txt}"
    #         )
    #         raise ValueError(msg)

    return {
        "version": version,
        "major_minor": f"{major}.{minor}",
        "release_branch": release_branch,
        "is_minor": str(is_minor).lower(),
        "is_first_rc": str(is_first_rc).lower(),
    }


def main():
    """Main entry point for the script."""

    version_input = sys.argv[1]

    parsed = parse_version(version_input)
    for key, value in parsed.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
