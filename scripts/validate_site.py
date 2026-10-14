#!/usr/bin/env python3
"""Validate the static site and, with --release, its public download metadata."""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
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
    ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    matching = [i for i in ET.parse(root / "site/appcast.xml").findall("./channel/item")
                if i.findtext(ns + "shortVersionString") == config["version"]]
    assert len(matching) == 1, "Require the reviewed release entry before deploying"
    enclosure = matching[0].find("enclosure")
    assert enclosure is not None and enclosure.attrib["url"] == expected
    assert enclosure.attrib.get(ns + "edSignature"), "Missing update archive signature"
    assert matching[0].findtext(ns + "minimumSystemVersion") in ["14.0", "14.0.0"]


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
