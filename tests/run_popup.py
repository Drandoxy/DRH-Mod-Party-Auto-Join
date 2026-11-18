"""Offline geometry test; does not launch or render DRH."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--haxe", default="haxe")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="party-popup-") as folder:
    runtime = Path(folder)
    shutil.copytree(root / "tests" / "fixtures", runtime, dirs_exist_ok=True)
    package = runtime / "mods" / "party_time_auto_game_joiner"
    package.mkdir(parents=True)
    shutil.copy2(root / "src" / "FriendPopupLayout.hx", package / "FriendPopupLayout.hx")
    shutil.copy2(root / "src" / "MemberStatus.hx", package / "MemberStatus.hx")
    for name in ("PartyState.hx", "PartyMember.hx"):
        shutil.copy2(root / "src" / name, package / name)
    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "PausedStateChecks", "--interp"], check=True)
    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "MemberStatusChecks", "--interp"], check=True)
    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "PopupHeightChecks", "--interp"], check=True)
