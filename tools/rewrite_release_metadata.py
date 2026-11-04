"""Prepare English GitHub Release descriptions without changing APK assets.

Default: dry-run. Use --apply only when intentionally editing public release metadata.
Requires GitHub CLI authenticated with permission to edit this repository's Releases.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

REPO = "111nndel/ArtOfficeCraft-Mobile"
ROOT = Path(__file__).resolve().parents[1]
TAG_RE = re.compile(r"^v(\d+\.\d+\.\d+)-alpha\.(\d+)$")
CYRILLIC = re.compile("[\u0400-\u052f]")


def gh(*args):
    run = subprocess.run(["gh", *args], check=True, capture_output=True, text=True)
    return run.stdout


def notes_for(tag):
    match = TAG_RE.fullmatch(tag)
    if not match:
        raise ValueError(f"Unexpected release tag: {tag}")
    version = match.group(1)
    candidates = [
        ROOT / "docs" / f"release-{tag[1:]}.md",
        ROOT / "docs" / f"release-{version}-alpha.1.md",
    ]
    source = next((path for path in candidates if path.is_file()), None)
    if source is None:
        raise FileNotFoundError(f"Missing English release notes for {tag}")
    notes = source.read_text(encoding="utf-8").strip()
    if CYRILLIC.search(notes):
        raise ValueError(f"Non-English release notes: {source}")
    for heading in ("## What's New", "## Known Limitations"):
        if heading not in notes:
            raise ValueError(f"Required section {heading!r} missing in {source}")
    return notes


def render(tag, old_body, assets):
    notes = notes_for(tag)
    apk_assets = [a["name"] for a in assets if a["name"].lower().endswith(".apk")]
    if len(apk_assets) != 1:
        raise ValueError(f"Expected exactly one APK asset for {tag}, got {apk_assets}")
    apk = apk_assets[0]
    download = (
        "## Download\n\n"
        f"- [Android ARM64 preview APK](https://github.com/{REPO}/releases/download/{tag}/{apk})\n"
        "- Requires an ARM64 Android device. This is a development preview, not a production release.\n"
        "- SHA-256 checksum: see `SHA256SUMS.txt` in the release assets.\n\n"
    )
    notes = notes.replace("## Known Limitations", download + "## Known Limitations", 1)
    source = re.search(r"(?m)^Source: ([0-9a-f]{40})\s*$", old_body)
    build = re.search(r"(?m)^Build: (https://github\.com/111nndel/ArtOfficeCraft-Mobile/actions/runs/\d+)\s*$", old_body)
    verification = (
        "\n\n## Build & Verification\n\n"
        "- Signed using the existing development preview certificate.\n"
        "- See the release assets for build metadata and checksums.\n"
    )
    if source:
        commit = source.group(1)
        verification += f"- Source commit: [`{commit[:12]}`](https://github.com/{REPO}/commit/{commit}).\n"
    if build:
        verification += f"- [GitHub Actions build and test logs]({build.group(1)}).\n"
    if not build:
        verification += "- Historical preview: validation coverage varies by version.\n"
    return notes + verification


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Actually update published GitHub release descriptions")
    parser.add_argument("--tag", help="Update a single release instead of all project alpha releases")
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "release-notes-review")
    args = parser.parse_args()

    tags = [args.tag] if args.tag else [
        row["tagName"] for row in json.loads(
            gh("release", "list", "--repo", REPO, "--limit", "200", "--json", "tagName")
        ) if TAG_RE.fullmatch(row["tagName"])
    ]
    args.output.mkdir(parents=True, exist_ok=True)
    for tag in tags:
        details = json.loads(
            gh("release", "view", tag, "--repo", REPO, "--json", "body,assets,tagName")
        )
        if details["tagName"] != tag:
            raise ValueError("GitHub release tag mismatch")
        body = render(tag, details.get("body", ""), details["assets"])
        destination = args.output / f"{tag}.md"
        destination.write_text(body + "\n", encoding="utf-8")
        # Keep a local copy of the original public description for rollback.
        (args.output / f"{tag}.original.md").write_text(details.get("body", ""), encoding="utf-8")
        if args.apply:
            gh("release", "edit", tag, "--repo", REPO, "--title",
               f"ArtOfficeCraft Mobile {tag}", "--notes-file", str(destination))
            print(f"Updated: {tag}")
        else:
            print(f"Preview only: {tag} => {destination}")
    print(f"{len(tags)} release descriptions {'updated' if args.apply else 'prepared; no GitHub metadata changed'}.")


if __name__ == "__main__":
    main()
