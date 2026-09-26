#!/usr/bin/env python3
"""Build/upgrade Macarchy without resetting settings, or explicitly install/restore a profile."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BUILD_VERSION = "0.22.1"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def profile(leader=False):
    text = (ROOT / "docs/config-examples/omarchy.toml").read_text()
    data = tomllib.loads(text)
    if leader:
        text = text.replace("mouse-modifier = 'alt'", "mouse-modifier = 'none'")
        # A modal alternative for users who need Option chords in applications.
        bindings = data["mode"]["main"]["binding"]
        lines = []
        for key, value in bindings.items():
            if key == "alt-semicolon":
                continue
            key = "backspace" if key == "alt-shift-esc" else key.removeprefix("alt-")
            commands = value if isinstance(value, list) else [value]
            lines.append(f"{key} = {json.dumps(['mode main', *commands])}")
        lines.append("esc = 'mode main'")
        # Only the known template is transformed; user files are never parsed and rewritten.
        prefix, rest = text.split("[mode.main.binding]", 1)
        _, rest = rest.split("[mode.resize.binding]", 1)
        # Keep the launcher and passthrough sections after the leader transformation.
        head, marker, tail = rest.partition("# All application shortcuts pass through;")
        text = prefix + "[mode.main.binding]\nf18 = 'mode macarchy'\n\n[mode.macarchy.binding]\n"
        text += "\n".join(lines) + "\n\n[mode.resize.binding]" + head + marker + tail
    tomllib.loads(text)
    return text


def hotkeys(text):
    data = tomllib.loads(text)
    lines = ["MACARCHY", "", "Super = Option (alt); ctrl = Control. Command is reserved for apps.",
             "Command+T/W/L/F/S/Q/Tab and Command+Shift shortcuts remain native.",
             "Left/Right: windows in this workspace. Tab: next numbered workspace.", ""]
    for mode, settings in data["mode"].items():
        lines += [mode.upper(), ""]
        for key, commands in settings["binding"].items():
            commands = commands if isinstance(commands, list) else [commands]
            label = " ; ".join(commands).replace('exec-and-forget "$HOME/.config/macarchy/action" ', "open ")
            lines.append(f"{key:32} {label}")
        lines.append("")
    return "\n".join(lines) + "\n"


def build_app(build_version=DEFAULT_BUILD_VERSION):
    bash = shutil.which("bash", path="/opt/homebrew/bin:/usr/local/bin")
    if not bash:
        raise SystemExit("Install Bash 5 first: brew install bash")
    run(bash, str(ROOT / "generate.sh"), "--ignore-xcodeproj", "--build-version", build_version, "--generate-git-hash", cwd=ROOT)
    run("swift", "build", "-c", "release", cwd=ROOT)
    bin_dir = Path(subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True).strip())
    destination = ROOT / ".local" / "macarchy.app"
    contents = destination / "Contents"
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)
    (contents / "Resources").mkdir(exist_ok=True)
    (contents / "Helpers").mkdir(exist_ok=True)
    shutil.copy2(bin_dir / "MacarchyApp", contents / "MacOS" / "macarchy")
    # Both SPM products would collide with the helper name if copied verbatim.
    shutil.copy2(bin_dir / "macarchy", contents / "Helpers" / "macarchy")
    shutil.copy2(ROOT / "docs/config-examples/default-config.toml", contents / "Resources" / "default-config.toml")
    shutil.copy2(ROOT / "resources/Assets.xcassets/AppIcon.appiconset/icon.png", contents / "Resources" / "AppIcon.png")
    for resource in bin_dir.glob("*.bundle"):
        shutil.copytree(resource, contents / "Resources" / resource.name, dirs_exist_ok=True)
    info = {
        "CFBundleExecutable": "macarchy", "CFBundleIdentifier": "com.hancengiz.macarchy",
        "CFBundleName": "macarchy", "CFBundlePackageType": "APPL",
        "CFBundleIconFile": "AppIcon", "CFBundleShortVersionString": build_version.split("-", 1)[0],
        "CFBundleVersion": build_version.split("-", 1)[0],
        "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
        "NSAppleEventsUsageDescription": "Launch applications from your configured shortcuts.",
    }
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    run("codesign", "--force", "--deep", "--sign", codesign_identity(), str(destination))
    run("codesign", "--verify", "--deep", "--strict", str(destination))
    print(f"Built {destination}")
    return destination

def codesign_identity():
    """Prefer a stable local identity so the Accessibility grant survives rebuilds."""
    listing = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True,
    ).stdout
    for line in listing.splitlines():
        if "Developer ID Application" in line:
            return line.split('"')[1]
    return "-"


def supports_safe_restart(cli):
    """Probe the OLD helper before replacing it; never signal an unknown version."""
    if not cli.is_file():
        return False
    try:
        result = subprocess.run([str(cli), "restart", "--help"], capture_output=True, text=True, timeout=10)
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def install_app(app, installed, backup):
    """Stage and verify first, then swap; restore the original on swap failure."""
    installed.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".macarchy-install-", dir=installed.parent) as directory:
        staging = Path(directory) / app.name
        previous = Path(directory) / "previous.app"
        shutil.copytree(app, staging)
        run("codesign", "--verify", "--deep", "--strict", str(staging))
        if installed.exists():
            shutil.copytree(installed, backup / app.name)
            os.replace(installed, previous)
        try:
            os.replace(staging, installed)
        except BaseException:
            if previous.exists():
                os.replace(previous, installed)
            raise


def restart_installed_app(installed, supported):
    if not supported:
        print("This previous version cannot restart safely. No signal was sent.")
        print(f"One-time manual step: quit the previous version, then open {installed}.")
        return
    try:
        result = subprocess.run(
            [str(installed / "Contents/Helpers/macarchy"), "restart"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            print(result.stdout.strip() or "Restart requested; the saved window session will be restored.")
            return
        detail = result.stderr.strip() or result.stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        detail = str(error)
    print(f"Safe restart was not completed: {detail}")
    print(f"No process was killed. If Macarchy is not running, open {installed}.")



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--leader", action="store_true", help="Use F18, then an unmodified key; suitable with VoiceOver")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build", action="store_true", help="Build/sign and upgrade the app; preserve existing config and Settings")
    mode.add_argument("--build-only", action="store_true", help="Build/sign the app without changing your desktop")
    mode.add_argument("--profile-only", action="store_true", help="Explicitly replace the installed fork's config with this profile (backs up first)")
    parser.add_argument("--build-version", default=DEFAULT_BUILD_VERSION, help="App and CLI version to embed when building")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--restore", type=Path, help="Restore a backup directory printed during installation")
    args = parser.parse_args()
    home = Path.home()
    config = home / ".macarchy.toml"
    xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "macarchy/macarchy.toml"
    if not config.exists() and xdg_config.exists():
        config = xdg_config
    helper = home / ".config/macarchy"
    if args.restore:
        backup = args.restore.expanduser().resolve()
        manifest = json.loads((backup / "manifest.json").read_text())
        config = Path(manifest.get("configPath", str(config)))
        if args.dry_run:
            print(f"Would restore {config} and {helper} from {backup}")
            return
        for name, target in [("macarchy.toml", config), ("macarchy", helper)]:
            source = backup / name
            if manifest[name]:
                if source.is_dir():
                    shutil.copytree(source, target, dirs_exist_ok=True)
                else:
                    shutil.copy2(source, target)
            elif target == config:
                target.unlink(missing_ok=True)
        print(f"Restored profile from {backup}. Restart your previous window manager app.")
        return
    text = profile(args.leader)
    if args.dry_run:
        if args.build and config.exists():
            print(f"Would build/sign and upgrade the app, preserving {config} and all Settings.")
        else:
            print(text)
        return
    app = build_app(args.build_version) if args.build or args.build_only else None
    if args.build_only:
        return
    if args.profile_only and not (home / "Applications/macarchy.app/Contents/Helpers/macarchy").is_file():
        parser.error("The fork is not installed yet. Use --build first")
    if not app and not args.profile_only:
        parser.error("Use --build to build and install, or --profile-only to update an installed fork")
    installed = home / "Applications/macarchy.app"
    upgrading = installed.exists()
    restart_supported = supports_safe_restart(installed / "Contents/Helpers/macarchy") if app and upgrading else False
    # Migrate legacy AeroSpace-Omarchy-era paths once, preserving user data.
    migrate_legacy_paths(home)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = home / ".config/macarchy/backups" / stamp
    backup.mkdir(parents=True)
    manifest = {"configPath": str(config)}
    for name, target in [("macarchy.toml", config), ("macarchy", helper)]:
        manifest[name] = target.exists()
        if target.is_dir():
            # The backups directory lives inside the helper dir; never back it up.
            shutil.copytree(target, backup / name, ignore=shutil.ignore_patterns("backups"))
        elif target.exists():
            shutil.copy2(target, backup / name)
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2))
    helper.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "macarchy/action", helper / "action")
    (helper / "action").chmod(0o755)
    menu = helper / "menu.jsonc"
    if not menu.exists():
        # Never overwrite user menu customizations; a missing sample installs fresh.
        shutil.copy2(ROOT / "macarchy/menu.jsonc.sample", menu)
    replace_profile = args.profile_only or (not config.exists() and not upgrading)
    if app:
        install_app(app, installed, backup)
        print(f"App: {installed}")
        print(f"Fork CLI: {installed}/Contents/Helpers/macarchy")
    if replace_profile:
        config.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=config.parent, delete=False) as file:
            file.write(text)
            temporary = file.name
        try:
            os.replace(temporary, config)
        finally:
            Path(temporary).unlink(missing_ok=True)
        print(f"Installed profile: {config}")
    else:
        print(f"Preserved existing configuration and Settings (profile not replaced): {config}")
    if replace_profile:
        (helper / "HOTKEYS.txt").write_text(hotkeys(text))
    if app:
        if upgrading:
            restart_installed_app(installed, restart_supported)
        else:
            print(f"Open {installed} and grant Accessibility access. Existing window managers were not stopped.")
    print(f"Backup: {backup}")
    print(f"Restore: python3 macarchy/install.py --restore {backup}")




def migrate_legacy_paths(home):
    """Move pre-rebrand paths (~/.aerospace.toml, ~/.config/aerospace/omarchy)
    to their macarchy equivalents, preserving user data once."""
    legacy_config = home / ".aerospace.toml"
    legacy_helper = home / ".config/aerospace/omarchy"
    config = home / ".macarchy.toml"
    xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "macarchy/macarchy.toml"
    helper = home / ".config/macarchy"
    if legacy_config.exists() and not config.exists() and not xdg_config.exists():
        os.replace(legacy_config, config)
    if legacy_helper.exists() and not helper.exists():
        helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(legacy_helper), str(helper))


if __name__ == "__main__":
    main()
