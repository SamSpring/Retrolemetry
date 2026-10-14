#!/usr/bin/env python3
"""Validate the static site and, with --release, its public download metadata."""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--release", action="store_true")
args = parser.parse_args()

config = json.loads((root / "site/release.json").read_text())
assert config["supportUrl"] == "https://ko-fi.com/samspring"
assert config["architecture"] == "universal"
assert config["minimumMacOS"] == "14.0"
repo = config["repositoryUrl"]
assert re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo)
if args.release:
    assert config["notarized"] is True
    assert config["publicDownloadVerified"] is True
    assert re.fullmatch(r"\d+\.\d+\.\d+", config["version"])
    assert re.fullmatch(r"[a-f0-9]{64}", config["sha256"])
    expected = f"{repo}/releases/download/v{config['version']}/Retrolemetry-{config['version']}.zip"
    assert config["downloadUrl"] == expected


class LocalFiles(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("href", "src") and value and not value.startswith("#"):
                url = urlsplit(value)
                if url.scheme:
                    assert url.scheme == "https"
                elif value != "./":
                    assert (root / "site" / url.path).is_file(), f"Missing site asset: {value}"


LocalFiles().feed((root / "site/index.html").read_text())
print("Site validation passed" + (" for release." if args.release else "."))
