#!/usr/bin/env python3
"""Exercise the real standard Sparkle UI in a separately identified test app.

Uses temporary keys, synthetic defaults and a loopback-only allowlisted server.
Does not install Retrolemetry, read its Keychain, or register login items.
Not a substitute for final notarized-production-app acceptance in a clean VM.
"""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--sparkle-tools", type=Path, default=ROOT / ".build/artifacts/sparkle/Sparkle/bin")
args = parser.parse_args()
out = args.output.resolve()
assert not out.is_relative_to(ROOT), "QA artifacts and keys must stay outside the repository"
out.mkdir(parents=True, exist_ok=False)
tools = args.sparkle_tools.resolve()
framework = tools.parent / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
identity = "io.github.SamSpring.Retrolemetry.UpdaterQA." + uuid.uuid4().hex
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def run(command, **kwargs):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr[-5000:] or result.stdout[-5000:])
    return result.stdout.strip()


allowed = {}


class Server(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        file = allowed.get(path)
        if not file:
            self.send_error(404)
            return
        payload = file.read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
base = "http://127.0.0.1:" + str(server.server_port)
threading.Thread(target=server.serve_forever, daemon=True).start()

with tempfile.TemporaryDirectory(prefix="retrolemetry-updater-keys-", dir="/private/tmp") as private:
    seed = Path(private) / "test-seed"
    wrong = Path(private) / "wrong-seed"
    public = run(["swift", ROOT / "scripts/qa_key.swift", seed])
    run(["swift", ROOT / "scripts/qa_key.swift", wrong])
    binary = out / "qa-binary"
    run(["swiftc", "-parse-as-library", ROOT / "scripts/qa_updater.swift",
         ROOT / "Sources/Retrolemetry/AppUpdater.swift", "-o", binary,
         "-F", framework.parent, "-framework", "Sparkle", "-Xlinker", "-rpath",
         "-Xlinker", "@executable_path/../Frameworks"])
    for build in ["1", "2"]:
        app = out / ("build" + build) / "Retrolemetry Updater QA.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copyfile(binary, contents / "MacOS/Retrolemetry")
        (contents / "MacOS/Retrolemetry").chmod(0o755)
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        info.update(CFBundleIdentifier=identity, CFBundleName="Retrolemetry Updater QA",
                    CFBundleDisplayName="Retrolemetry Updater QA", CFBundleVersion=build,
                    CFBundleShortVersionString="0.0." + build, LSUIElement=False,
                    SUPublicEDKey=public, QARoot=str(out), QAFeedBase=base,
                    SUEnableAutomaticChecks=False,
                    NSAppTransportSecurity={"NSAllowsLocalNetworking": True})
        info.pop("CFBundleIconFile", None)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        env = dict(os.environ)
        env.pop("CODESIGN_IDENTITY", None)
        run(["sh", ROOT / "scripts/embed_sparkle.sh", app, framework], env=env)
        run(["codesign", "--force", "--sign", "-", app])
        run(["codesign", "--verify", "--deep", "--strict", app])
    newer = out / "build2/Retrolemetry Updater QA.app"
    archives = out / "archives"
    archives.mkdir()
    archive = archives / "Retrolemetry-QA.zip"
    run(["ditto", "-c", "-k", "--keepParent", newer, archive])
    (archives / "Retrolemetry-QA.md").write_text("# Private updater test\n\nSynthetic data only. Never publish.\n")
    run([tools / "generate_appcast", "--ed-key-file", seed, "--maximum-deltas", "0",
         "--embed-release-notes", "--download-url-prefix", base + "/", archives])
    feed = archives / "appcast.xml"
    enclosure = ET.parse(feed).find("./channel/item/enclosure")
    signature = enclosure.attrib[ns + "edSignature"]
    run([tools / "sign_update", "--ed-key-file", seed, "--verify", archive, signature])
    run([tools / "sign_update", "--ed-key-file", seed, "--verify", feed])
    allowed["/Retrolemetry-QA.zip"] = archive
    allowed["/valid.xml"] = feed
    for case in ["tampered", "wrong-key", "wrong-feed", "no-update"]:
        target = out / (case + ".xml")
        tree = ET.parse(feed)
        enc = tree.find("./channel/item/enclosure")
        if case == "tampered":
            bad = out / "tampered.zip"
            data = bytearray(archive.read_bytes()); data[len(data) // 2] ^= 1
            bad.write_bytes(data)
            allowed["/tampered.zip"] = bad
            enc.set("url", base + "/tampered.zip")
        elif case == "wrong-key":
            bad_signature = run([tools / "sign_update", "--ed-key-file", wrong, "-p", archive])
            enc.set(ns + "edSignature", bad_signature)
        elif case == "no-update":
            tree.find("./channel/item/" + ns + "version").text = "1"
        tree.write(target, encoding="utf-8", xml_declaration=True)
        run([tools / "sign_update", "--ed-key-file", wrong if case == "wrong-feed" else seed, target])
        allowed["/" + case + ".xml"] = target

    events_path = out / "events.jsonl"
    results = {}
    for case in ["no-update", "tampered", "wrong-key", "wrong-feed", "valid"]:
        (out / "scenario").write_text(case)
        app = out / ("installed-" + case) / "Retrolemetry Updater QA.app"
        run(["ditto", "--noextattr", "--norsrc", out / "build1/Retrolemetry Updater QA.app", app])
        before = hashlib.sha256((app / "Contents/MacOS/Retrolemetry").read_bytes()).hexdigest()
        run(["open", "-n", app])
        deadline = time.monotonic() + 65
        complete = []
        while time.monotonic() < deadline:
            events = [json.loads(line) for line in events_path.read_text().splitlines()] if events_path.exists() else []
            complete = [e for e in events if e["scenario"] == case and e["event"] in
                        ["no-update-visible", "rejected", "relaunched-new-build", "timeout"]]
            if complete:
                break
            time.sleep(0.2)
        time.sleep(1.5)
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        results[case] = {"events": complete, "installedBuild": info["CFBundleVersion"],
                         "executableUnchanged": before == hashlib.sha256((app / "Contents/MacOS/Retrolemetry").read_bytes()).hexdigest()}
        (out / "result.json").write_text(json.dumps(results, indent=2) + "\n")
        if not complete or complete[-1]["event"] == "timeout":
            raise RuntimeError("QA incomplete for " + case + "; retain output for diagnosis")
        assert all(e["settingsPreserved"] for e in complete)
        case_events = [e for e in events if e["scenario"] == case]
        assert len({e["layoutDigest"] for e in case_events}) == 1, "Layout bytes changed"
        if case in ["tampered", "wrong-key", "wrong-feed"]:
            assert any("improperly signed" in e.get("text", "") for e in case_events), "Must observe a signature rejection, not a generic failure"
        assert info["CFBundleVersion"] == ("2" if case == "valid" else "1")
        run(["codesign", "--verify", "--deep", "--strict", app])
        if case != "valid":
            assert results[case]["executableUnchanged"]
        print(case + ": passed", flush=True)
    run(["defaults", "delete", identity])
    server.shutdown()
    print("All private native updater cases passed. Temporary keys deleted; production app untouched.")
