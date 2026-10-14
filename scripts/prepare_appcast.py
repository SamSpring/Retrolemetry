#!/usr/bin/env python3
"""Prepare and verify a signed appcast privately; never publishes anything.

Accept only a final, notarized/stapled Retrolemetry ZIP. The private key is
accessed through Retrolemetry's dedicated Keychain account, not an environment
variable or repository file. Stage outside the source checkout.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ACCOUNT = "io.github.SamSpring.Retrolemetry.sparkle"
FEED = "https://samspring.github.io/Retrolemetry/appcast.xml"
REPO = "https://github.com/SamSpring/Retrolemetry"
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--previous", type=Path, help="Reviewed previous private feed staging")
parser.add_argument("--sparkle-tools", type=Path, default=ROOT / ".build/artifacts/sparkle/Sparkle/bin")
args = parser.parse_args()
archive, output = args.archive.resolve(), args.output.resolve()
assert not output.is_relative_to(ROOT), "Stage artifacts outside the repository"
assert archive.is_file() and not output.exists(), "Require a final archive and a NEW staging folder"
tools = args.sparkle_tools.resolve()


def run(command):
    return subprocess.check_output(list(map(str, command)), text=True).strip()


with tempfile.TemporaryDirectory(prefix="retrolemetry-feed-validation-", dir="/private/tmp") as private:
    run(["ditto", "-x", "-k", archive, private])
    app = Path(private) / "Retrolemetry.app"
    assert sorted(p.name for p in Path(private).iterdir()) == ["Retrolemetry.app"], "ZIP must contain only the app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    source = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "io.github.SamSpring.Retrolemetry"
    assert info["SUFeedURL"] == FEED and info["SUPublicEDKey"] == source["SUPublicEDKey"]
    assert info["SURequireSignedFeed"] is True and info["SUVerifyUpdateBeforeExtraction"] is True
    assert run([tools / "generate_keys", "--account", ACCOUNT, "-p"]) == info["SUPublicEDKey"]
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    assert re.fullmatch(r"\d+\.\d+\.\d+", version) and re.fullmatch(r"[1-9]\d*", build)
    assert archive.name == f"Retrolemetry-{version}.zip"
    assert info["LSMinimumSystemVersion"] == "14.0"
    assert set(run(["lipo", "-archs", app / "Contents/MacOS/Retrolemetry"]).split()) == {"arm64", "x86_64"}
    run(["codesign", "--verify", "--deep", "--strict", app])
    signature = subprocess.run(["codesign", "-dvv", str(app)], capture_output=True, text=True, check=True).stderr
    assert "Authority=Developer ID Application:" in signature and "runtime" in signature
    run(["xcrun", "stapler", "validate", app])
    run(["spctl", "--assess", "--type", "execute", app])
    output.mkdir(parents=True)
    if args.previous:
        previous = args.previous.resolve()
        old = previous / "appcast.xml"
        assert old.is_file()
        run([tools / "sign_update", "--account", ACCOUNT, "--verify", old])
        for item in ET.parse(old).findall("./channel/item"):
            assert int(item.findtext(NS + "version")) < int(build), "Build numbers must increase"
        shutil.copyfile(old, output / "appcast.xml")
        for path in previous.iterdir():
            if re.fullmatch(r"Retrolemetry-\d+\.\d+\.\d+\.(zip|md)", path.name):
                assert path.is_file() and not path.is_symlink()
                shutil.copyfile(path, output / path.name)
    staged = output / archive.name
    assert not staged.exists(), "Never replace released archive names"
    shutil.copyfile(archive, staged)
    shutil.copyfile(ROOT / "RELEASE_NOTES.md", output / f"Retrolemetry-{version}.md")
    run([tools / "generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
         "--versions", build, "--download-url-prefix", f"{REPO}/releases/download/v{version}/",
         "--embed-release-notes", output])
    feed = output / "appcast.xml"
    run([tools / "sign_update", "--account", ACCOUNT, "--verify", feed])
    item = next(i for i in ET.parse(feed).findall("./channel/item") if i.findtext(NS + "version") == build)
    enclosure = item.find("enclosure")
    expected = f"{REPO}/releases/download/v{version}/{archive.name}"
    assert enclosure.attrib["url"] == expected
    assert int(enclosure.attrib["length"]) == archive.stat().st_size
    ed_signature = enclosure.attrib[NS + "edSignature"]
    assert len(base64.b64decode(ed_signature, validate=True)) == 64
    assert item.findtext(NS + "minimumSystemVersion") in ["14.0", "14.0.0"]
    assert item.findtext(NS + "hardwareRequirements") in [None, "arm64,x86_64", "x86_64,arm64"]
    assert item.find("description") is not None
    run([tools / "sign_update", "--account", ACCOUNT, "--verify", staged, ed_signature])
    checksum = hashlib.sha256(staged.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  {archive.name}\n")
    (output / "validation.json").write_text(json.dumps({
        "version": version, "build": build, "sha256": checksum,
        "feedUrl": FEED, "downloadUrl": expected, "signedFeedVerified": True,
        "signedArchiveVerified": True, "notarized": True, "published": False
    }, indent=2) + "\n")
    print("Signed feed and exact notarized ZIP verified in private staging. Nothing published.")
