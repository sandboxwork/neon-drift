#!/usr/bin/env python3
"""Export an isolated Godot source copy to Xcode; optionally archive on macOS.

Unsigned project: python3 tools/export_ios.py --unsigned --godot /path/to/godot
Signed project:   IOS_TEAM_ID=... IOS_BUNDLE_ID=... python3 tools/export_ios.py
Archive + IPA:    add --archive --ipa (requires Xcode signing credentials).
This script never uploads an app or modifies the source export presets.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = "4.6.3"
UNSIGNED_TEAM = "0000000000"


def run(command: list[str], **kwargs) -> None:
    print("+", " ".join(map(str, command)), flush=True)
    subprocess.run(command, check=True, **kwargs)


def stage_source(stage: Path) -> None:
    for pattern in ("*.gd", "*.uid", "*.tscn", "*.txt", "project.godot", "export_presets.cfg", "LICENSE"):
        for source in ROOT.glob(pattern):
            shutil.copy2(source, stage / source.name)
    shutil.copytree(ROOT / "assets", stage / "assets", ignore=shutil.ignore_patterns("*.import"))


def configure_preset(path: Path, options: dict) -> None:
    text = path.read_text()
    marker = "[preset.1.options]"
    head, body = text.split(marker, 1)
    for key, value in options.items():
        rendered = str(value).lower() if isinstance(value, bool) else json.dumps(str(value))
        line = f"{key}={rendered}"
        pattern = rf"^{re.escape(key)}=.*$"
        if re.search(pattern, body, flags=re.M):
            body = re.sub(pattern, lambda _: line, body, flags=re.M)
        else:
            body += "\n" + line + "\n"
    path.write_text(head + marker + body)


def validate_project(output: Path, bundle_id: str) -> dict:
    project = output / "neondrift.xcodeproj" / "project.pbxproj"
    if not project.is_file() or not (output / "neondrift.pck").is_file():
        raise RuntimeError("Godot did not produce an Xcode project and game pack.")
    if platform.system() == "Darwin":
        run(["plutil", "-lint", str(project)])
    info_path = output / "neondrift" / "neondrift-Info.plist"
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    orientations = info.get("UISupportedInterfaceOrientations", [])
    if set(orientations) != {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}:
        raise RuntimeError(f"Unexpected iOS orientations: {orientations}")
    identifiers = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([A-Za-z0-9.-]+)"?;', project.read_text())
    if info.get("CFBundleIdentifier") not in {bundle_id, "$(PRODUCT_BUNDLE_IDENTIFIER)"} or not identifiers or set(identifiers) != {bundle_id}:
        raise RuntimeError("Exported Bundle ID differs from requested identifier.")
    manifests = list(output.rglob("PrivacyInfo.xcprivacy"))
    if not manifests:
        raise RuntimeError("Missing Apple privacy manifest.")
    # Only check the app manifest, not engine/framework manifests.
    manifest = next((path for path in manifests if path.parent == info_path.parent), manifests[0])
    with manifest.open("rb") as stream:
        privacy = plistlib.load(stream)
    if privacy.get("NSPrivacyTracking", False) or privacy.get("NSPrivacyCollectedDataTypes", []):
        raise RuntimeError("Unexpected tracking/data collection in offline game export.")
    return {"project": str(project.parent), "info_plist": str(info_path), "privacy_manifest": str(manifest)}


def main() -> None:
    default_godot = os.environ.get("GODOT", str(ROOT / ".cache/godot/godot"))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=default_godot)
    parser.add_argument("--templates", type=Path, default=ROOT / ".cache/godot/templates")
    parser.add_argument("--team-id", default=os.environ.get("IOS_TEAM_ID", ""))
    parser.add_argument("--bundle-id", default=os.environ.get("IOS_BUNDLE_ID", ""))
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--build-number", default="1")
    parser.add_argument("--profile-uuid", default="", help="Installed App Store provisioning profile UUID for manual signing.")
    parser.add_argument("--profile-name", default="", help="Installed profile name; must accompany --profile-uuid.")
    parser.add_argument("--signing-identity", default="Apple Distribution", help="Certificate name or SHA-1 fingerprint in the Mac keychain.")
    parser.add_argument("--output", type=Path, default=ROOT / "build/ios")
    parser.add_argument("--unsigned", action="store_true", help="Generate a review/build project with empty signing team; no installable IPA.")
    parser.add_argument("--archive", action="store_true")
    parser.add_argument("--ipa", action="store_true", help="Export an App Store IPA from the archive; does not upload it.")
    args = parser.parse_args()
    if args.unsigned and (args.archive or args.ipa):
        parser.error("--unsigned cannot create a signed archive/IPA.")
    if bool(args.profile_uuid) != bool(args.profile_name):
        parser.error("Manual signing requires both --profile-uuid and --profile-name.")
    if args.profile_uuid and (args.unsigned or not re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", args.profile_uuid)):
        parser.error("Use a valid profile UUID with a real signing team, without --unsigned.")
    if (args.archive or args.ipa) and platform.system() != "Darwin":
        parser.error("Archiving and signing require macOS with Xcode.")
    if not args.unsigned and not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("Set IOS_TEAM_ID to your 10-character Apple team ID, or use --unsigned.")
    bundle_id = args.bundle_id or ("com.example.neondrift" if args.unsigned else "")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id):
        parser.error("Set IOS_BUNDLE_ID to your reverse-DNS app identifier.")
    if not args.unsigned and (bundle_id.startswith("com.example.") or args.team_id == UNSIGNED_TEAM):
        parser.error("Replace the unsigned example identifier and team before signing.")
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or not re.fullmatch(r"[1-9]\d*", args.build_number):
        parser.error("Use a version such as 1.0.0 and a positive integer build number.")
    binary = shutil.which(args.godot)
    if not binary:
        parser.error("Godot not found. Run tools/install_godot.py or pass --godot.")
    version = subprocess.check_output([binary, "--version"], text=True).strip()
    if not version.startswith(VERSION + ".stable"):
        parser.error(f"Expected Godot {VERSION}.stable, found {version}.")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Output is not empty. Use --output with a new directory to preserve existing builds.")
    output.mkdir(parents=True, exist_ok=True)
    options = {"application/app_store_team_id": UNSIGNED_TEAM if args.unsigned else args.team_id,
               "application/bundle_identifier": bundle_id, "application/short_version": args.version,
               "application/version": args.build_number, "application/export_project_only": True}
    if args.profile_uuid:
        options.update({"application/provisioning_profile_uuid_release": args.profile_uuid,
                        "application/provisioning_profile_specifier_release": args.profile_name,
                        "application/code_sign_identity_release": args.signing_identity})
    template = args.templates.resolve() / "ios.zip"
    if template.is_file():
        options.update({"custom_template/debug": str(template), "custom_template/release": str(template)})
    with tempfile.TemporaryDirectory(prefix="neon-ios-") as staging:
        stage = Path(staging)
        stage_source(stage)
        configure_preset(stage / "export_presets.cfg", options)
        run([binary, "--headless", "--editor", "--path", str(stage), "--import", "--quit"])
        run([binary, "--headless", "--path", str(stage), "--export-release", "iOS", str(output / "neondrift.ipa")])
    if args.unsigned:
        # The Godot exporter requires a nonempty Team ID even for project-only
        # export. Remove the sentinel from all generated text before handoff.
        for path in output.rglob("*"):
            if path.suffix in {".pbxproj", ".plist", ".xcconfig"}:
                text = path.read_text()
                if path.suffix == ".pbxproj":
                    text = re.sub(r'((?:DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*)"?'
                                  + UNSIGNED_TEAM + r'"?;', r'\1"";', text)
                elif path.suffix == ".plist":
                    text = text.replace("<string>" + UNSIGNED_TEAM + "</string>", "<string></string>")
                path.write_text(text)
    receipt = validate_project(output, bundle_id)
    receipt.update({"engine": version, "bundle_id": bundle_id, "version": args.version,
                    "build_number": args.build_number, "signed": False,
                    "team_id": "" if args.unsigned else args.team_id,
                    "signing_style": "manual" if args.profile_uuid else "automatic",
                    "profile_uuid": args.profile_uuid, "profile_name": args.profile_name,
                    "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    export_options = output / "ExportOptions.plist"
    export_settings = {"method": "app-store-connect", "teamID": args.team_id,
                       "signingStyle": receipt["signing_style"], "destination": "export",
                       "manageAppVersionAndBuildNumber": False}
    if args.profile_uuid:
        export_settings.update({"signingCertificate": args.signing_identity,
                                "provisioningProfiles": {bundle_id: args.profile_name}})
    if not args.unsigned:
        export_options.write_bytes(plistlib.dumps(export_settings))
    if args.archive or args.ipa:
        archive = output / "neondrift.xcarchive"
        signing_args = [f"DEVELOPMENT_TEAM={args.team_id}"]
        if args.profile_uuid:
            signing_args += ["CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={args.signing_identity}",
                             f"PROVISIONING_PROFILE_SPECIFIER={args.profile_name}"]
        else:
            signing_args += ["-allowProvisioningUpdates", "CODE_SIGN_STYLE=Automatic"]
        run(["xcodebuild", "-project", receipt["project"], "-scheme", "neondrift", "-configuration", "Release",
             "-destination", "generic/platform=iOS", "-archivePath", str(archive),
             *signing_args, "archive"])
        receipt["archive"] = str(archive)
        receipt["signed"] = True
        if args.ipa:
            run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(output / "ipa"),
                 "-exportOptionsPlist", str(export_options), *([] if args.profile_uuid else ["-allowProvisioningUpdates"])])
            receipt["ipa_directory"] = str(output / "ipa")
    (output / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
