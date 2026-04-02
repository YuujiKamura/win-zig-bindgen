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

    # Use utf-8-sig to handle potential BOM
    with open(ROOTS_FILE, "r", encoding="utf-8-sig") as f:
        config = json.load(f)

    roots = config.get("roots", {})
    ifaces = roots.get("interfaces", [])
    delegates = roots.get("delegates", [])
    enums = roots.get("enums", [])
    structs = roots.get("structs", [])

    all_types = ifaces + delegates + enums + structs
    print(f"DEBUG: Read {len(all_types)} types from {ROOTS_FILE}")
    
    # Verify IApplication is in the list
    if "Microsoft.UI.Xaml.IApplication" in all_types:
        print("DEBUG: IApplication found in target list.")
    else:
        print("WARNING: IApplication MISSING from target list!")

    winmd_path = r"C:\Users\yuuji\.nuget\packages\microsoft.windowsappsdk\1.4.230822000\lib\uap10.0\Microsoft.Windows.ApplicationModel.Resources.winmd"
    xaml_winmd = r"C:\Users\yuuji\.nuget\packages\microsoft.windowsappsdk\1.4.230822000\lib\uap10.0\Microsoft.UI.Xaml.winmd"
    
    cmd = [
        "zig", "build", "run",
        "--",
        "--winmd", winmd_path,
        "--winmd", xaml_winmd,  # Add second WinMD
        "--deploy", OUTPUT_FILE,
        "--winrt-import", "winrt.zig",
    ]

    for t in all_types:
        cmd.extend(["--iface", t])

    print(f"Running bindgen for {len(all_types)} types...")
    
    result = subprocess.run(cmd, cwd=BINDGEN_DIR)
    if result.returncode == 0:
        print(f"Successfully generated {OUTPUT_FILE}")
    else:
        print(f"Error: bindgen failed with exit code {result.returncode}")
        sys.exit(result.returncode)

if __name__ == "__main__":
    main()
