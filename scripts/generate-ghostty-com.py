import json
import subprocess
import os
import sys

# Paths
BINDGEN_DIR = r"C:\Users\yuuji\win-zig-bindgen"
GHOSTTY_DIR = r"C:\Users\yuuji\ghostty-win"
ROOTS_FILE = os.path.join(BINDGEN_DIR, "winui_roots.json")
OUTPUT_FILE = os.path.join(GHOSTTY_DIR, "src", "apprt", "winui3", "com_generated.zig")

def main():
    if not os.path.exists(ROOTS_FILE):
        print(f"Error: {ROOTS_FILE} not found")
        sys.exit(1)

    with open(ROOTS_FILE, "r", encoding="utf-8") as f:
        config = json.load(f)

    roots = config.get("roots", {})
    ifaces = roots.get("interfaces", [])
    delegates = roots.get("delegates", [])
    enums = roots.get("enums", [])
    structs = roots.get("structs", [])

    all_types = ifaces + delegates + enums + structs

    # Explicitly use SDK 1.4 for the Resources WinMD to avoid parser issues with 1.6
    # and ensure compatibility with the current ghostty-win prebuilt runtime.
    winmd_path = r"C:\Users\yuuji\.nuget\packages\microsoft.windowsappsdk\1.4.230822000\lib\uap10.0\Microsoft.Windows.ApplicationModel.Resources.winmd"
    
    if not os.path.exists(winmd_path):
        winmd_path = r"C:\Users\yuuji\ghostty-win\xaml\prebuilt\runtime\x64\Microsoft.WindowsAppRuntime.winmd"

    cmd = [
        "zig", "build", "run",
        "--",
        "--winmd", winmd_path,
        "--deploy", OUTPUT_FILE,
        "--winrt-import", "winrt.zig",
    ]

    for t in all_types:
        cmd.extend(["--iface", t])

    print(f"Running bindgen for {len(all_types)} types (Auto-discovery mode)...")
    
    result = subprocess.run(cmd, cwd=BINDGEN_DIR)
    if result.returncode == 0:
        print(f"Successfully generated {OUTPUT_FILE}")
    else:
        print(f"Error: bindgen failed with exit code {result.returncode}")
        sys.exit(result.returncode)

if __name__ == "__main__":
    main()
