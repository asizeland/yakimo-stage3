#!/usr/bin/python3
import os
import sys

args = sys.argv[1:]
glibc_bound = False
converted = []
index = 0
while index < len(args):
    arg = args[index]
    if arg == "--":
        break
    converted.append(arg)
    if arg == "--setenv" and index + 2 < len(args) and args[index + 1] == "LD_LIBRARY_PATH":
        value = args[index + 2]
        converted.extend([args[index + 1], value])
        index += 3
        if "/pkg/deps/glibc/" in value:
            glibc_bound = True
        continue
    index += 1

if glibc_bound:
    root = os.environ["YAKIMO_IMAGE_ROOT"]
    loader = os.path.realpath(os.path.join(root, "lib64/ld-linux-x86-64.so.2"))
    if not os.path.isfile(loader):
        raise SystemExit(f"packaged glibc loader is unavailable: {loader}")
    for directory in ("/usr/lib/x86_64-linux-gnu", "/lib/x86_64-linux-gnu"):
        if os.path.isdir(directory):
            for position in range(0, len(converted) - 2):
                if converted[position:position + 2] == ["--setenv", "LD_LIBRARY_PATH"]:
                    converted[position + 2] += ":" + directory
    converted.extend(["--ro-bind", loader, "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"])
    converted.extend(["--tmpfs", "/usr/lib"])
    for entry in sorted(os.scandir("/usr/lib"), key=lambda item: item.name):
        converted.extend(["--ro-bind", entry.path, f"/usr/lib/{entry.name}"])
    package_root = os.path.dirname(os.path.dirname(loader))
    packaged_lib = os.path.join(package_root, "usr/lib")
    for entry in sorted(os.scandir(packaged_lib), key=lambda item: item.name):
        if not entry.is_dir(follow_symlinks=False):
            converted.extend(["--ro-bind", entry.path, f"/usr/lib/{entry.name}"])

converted.extend(args[index:])
os.execv("/usr/bin/bwrap", ["/usr/bin/bwrap", *converted])
