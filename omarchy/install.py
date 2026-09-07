#!/usr/bin/env python3
"""Install the fork's desktop profile, or restore a previous installation."""
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


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def profile(stock=False, leader=False):
    text = (ROOT / "docs/config-examples/omarchy.toml").read_text()
    if stock:
        text = text.replace("start-at-login = true", "start-at-login = false")
        text = text.replace("default-root-container-layout = 'scrolling'", "default-root-container-layout = 'tiles'")
        text = text.replace("scrolling-column-width = 49\n", "")
        text = text.replace("adopt-native-window-resize = true\n", "")
        text = text.replace("enable-mouse-edge-focus = true\n", "")
        text = text.replace("keep-floating-windows-on-top = true\n", "")
        text = text.replace("warn-about-shortcut-conflicts = true\n", "")
        text = text.replace("show-system-mode-overlay = true\n", "")
        # Upstream AeroSpace cannot render the fork's launcher panel; keep stock honest.
        text = text.replace("alt-space = 'mode omarchy-menu'\n", "")
        text = text.replace(
            "# All application shortcuts pass through; use the same chord to resume management.\n"
            "[mode.omarchy-menu.binding]\nalt-space = 'mode main'\nesc = 'mode main'\n\n",
            "",
        )
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
        text = prefix + "[mode.main.binding]\nf18 = 'mode omarchy'\n\n[mode.omarchy.binding]\n"
        text += "\n".join(lines) + "\n\n[mode.resize.binding]" + head + marker + tail
    tomllib.loads(text)
    return text


def hotkeys(text):
    data = tomllib.loads(text)
    lines = ["AEROSPACE / OMARCHY", "", "Super = Option (alt); ctrl = Control. Command is reserved for apps.",
             "Command+T/W/L/F/S/Q/Tab and Command+Shift shortcuts remain native.",
             "Left/Right: windows in this workspace. Tab: next numbered workspace.", ""]
    for mode, settings in data["mode"].items():
        lines += [mode.upper(), ""]
        for key, commands in settings["binding"].items():
            commands = commands if isinstance(commands, list) else [commands]
            label = " ; ".join(commands).replace('exec-and-forget "$HOME/.config/aerospace/omarchy/action" ', "open ")
            lines.append(f"{key:32} {label}")
        lines.append("")
    return "\n".join(lines) + "\n"


def build_app():
    bash = shutil.which("bash", path="/opt/homebrew/bin:/usr/local/bin")
    if not bash:
        raise SystemExit("Install Bash 5 first: brew install bash")
    run(bash, str(ROOT / "generate.sh"), "--ignore-xcodeproj", "--build-version", "0.22.0-Omarchy", cwd=ROOT)
    run("swift", "build", "-c", "release", "-Xswiftc", "-DOMARCHY", cwd=ROOT)
    bin_dir = Path(subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True).strip())
    destination = ROOT / ".local" / "AeroSpace-Omarchy.app"
    contents = destination / "Contents"
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)
    (contents / "Resources").mkdir(exist_ok=True)
    (contents / "Helpers").mkdir(exist_ok=True)
    shutil.copy2(bin_dir / "AeroSpaceApp", contents / "MacOS" / "AeroSpace")
    # Default macOS volumes are case-insensitive: AeroSpace and aerospace collide.
    shutil.copy2(bin_dir / "aerospace", contents / "Helpers" / "aerospace")
    shutil.copy2(ROOT / "docs/config-examples/default-config.toml", contents / "Resources" / "default-config.toml")
    for resource in bin_dir.glob("*.bundle"):
        shutil.copytree(resource, contents / "Resources" / resource.name, dirs_exist_ok=True)
    info = {
        "CFBundleExecutable": "AeroSpace", "CFBundleIdentifier": "com.hancengiz.aerospace",
        "CFBundleName": "AeroSpace Omarchy", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.22.0", "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
        "NSAppleEventsUsageDescription": "Launch applications from your configured shortcuts.",
    }
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    run("codesign", "--force", "--deep", "--sign", "-", str(destination))
    print(f"Built {destination}")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stock", action="store_true", help="Shortcut fix for upstream AeroSpace; no scrolling")
    parser.add_argument("--leader", action="store_true", help="Use F18, then an unmodified key; suitable with VoiceOver")
    parser.add_argument("--build", action="store_true", help="Build and install the fork as a separate app")
    parser.add_argument("--build-only", action="store_true", help="Build the app without changing your desktop")
    parser.add_argument("--profile-only", action="store_true", help="Update shortcuts for an already installed fork")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--restore", type=Path, help="Restore a backup directory printed during installation")
    args = parser.parse_args()
    if args.stock and (args.build or args.build_only):
        parser.error("--stock cannot be combined with --build or --build-only")
    home = Path.home()
    config = home / ".aerospace.toml"
    helper = home / ".config/aerospace/omarchy"
    if args.restore:
        backup = args.restore.expanduser().resolve()
        manifest = json.loads((backup / "manifest.json").read_text())
        if args.dry_run:
            print(f"Would restore {config} and {helper} from {backup}")
            return
        for name, target in [("aerospace.toml", config), ("omarchy", helper)]:
            source = backup / name
            if manifest[name]:
                if source.is_dir():
                    shutil.copytree(source, target, dirs_exist_ok=True)
                else:
                    shutil.copy2(source, target)
            elif target == config:
                target.unlink(missing_ok=True)
        print(f"Restored profile from {backup}. Restart your previous AeroSpace app.")
        return
    text = profile(args.stock, args.leader)
    if args.dry_run:
        print(text)
        return
    app = build_app() if args.build or args.build_only else None
    if args.build_only:
        return
    if args.profile_only and not (home / "Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace").is_file():
        parser.error("The fork is not installed yet. Use --build first")
    if not args.stock and not app and not args.profile_only:
        parser.error("Use --build for the fork, --profile-only to update it, or --stock for upstream AeroSpace")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = home / ".config/aerospace/backups" / stamp
    backup.mkdir(parents=True)
    manifest = {}
    for name, target in [("aerospace.toml", config), ("omarchy", helper)]:
        manifest[name] = target.exists()
        if target.is_dir():
            shutil.copytree(target, backup / name)
        elif target.exists():
            shutil.copy2(target, backup / name)
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2))
    helper.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "omarchy/action", helper / "action")
    (helper / "action").chmod(0o755)
    menu = helper / "menu.jsonc"
    if not menu.exists():
        # Never overwrite user menu customizations; a missing sample installs fresh.
        shutil.copy2(ROOT / "omarchy/menu.jsonc.sample", menu)
    (helper / "HOTKEYS.txt").write_text(hotkeys(text))
    with tempfile.NamedTemporaryFile(mode="w", dir=config.parent, delete=False) as file:
        file.write(text)
        temporary = file.name
    os.replace(temporary, config)
    if app:
        installed = home / "Applications" / app.name
        if installed.exists():
            shutil.copytree(installed, backup / app.name)
        shutil.copytree(app, installed, dirs_exist_ok=True)
        run("defaults", "write", "com.hancengiz.aerospace", "displayStyle", "-string", "i3Ordered")
        print(f"App: {installed}")
        print("Quit the existing AeroSpace, then open this app and grant Accessibility access.")
        print(f"Fork CLI: {installed}/Contents/Helpers/aerospace")
    print(f"Installed: {config}")
    print(f"Backup: {backup}")
    print(f"Restore: python3 omarchy/install.py --restore {backup}")


if __name__ == "__main__":
    main()
