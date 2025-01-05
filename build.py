import argparse
from enum import Enum
import subprocess
from fnmatch import filter as fnmatch_filter
from os.path import isdir, join
import shutil

supported_oses = [
    "darwin",
    "essence",
    "linux",
    "windows",
    "freebsd",
    "netbsd",
    "openbsd",
    "haiku",
    "freestanding",
    "wasi",
    "js",
    "orca",
]

supported_architectures = [
    "i386",
    "amd64",
    "arm64",
    "arm32",
    "riscv64",
    "wasm32",
    "wasm64p32",
    "amd64_sysv",
    "amd64_win64",
]

supported_targets = [
    "darwin_amd64",
    "darwin_arm64",
    "essence_amd64",
    "linux_i386",
    "linux_amd64",
    "linux_arm64",
    "linux_arm32",
    "linux_riscv64",
    "windows_i386",
    "windows_amd64",
    "freebsd_i386",
    "freebsd_amd64",
    "freebsd_arm64",
    "netbsd_amd64",
    "netbsd_arm64",
    "openbsd_amd64",
    "haiku_amd64",
    "freestanding_wasm32",
    "wasi_wasm32",
    "js_wasm32",
    "orca_wasm32",
    "freestanding_wasm64p32",
    "js_wasm64p32",
    "wasi_wasm64p32",
    "freestanding_amd64_sysv",
    "freestanding_amd64_win64",
    "freestanding_arm64",
    "freestanding_arm32",
    "freestanding_riscv64",
]


def odin_path() -> str:
    import shutil

    return shutil.which("odin") or "odin"


def get_vendor_path(rel: str = "") -> str:
    # odin_path/vendor/
    import os

    path = os.path.join(os.path.dirname(odin_path()), "vendor", rel)
    if not os.path.exists(path):
        return
    return path


def host_os() -> str:
    import platform

    os = platform.system().lower()
    if os == "linux":
        return "linux"
    if os == "darwin":
        return "darwin"
    if os == "windows":
        return "windows"
    return os


def host_arch() -> str:
    import platform

    arch = platform.machine().lower()
    if arch == "x86_64":
        return "amd64"
    if arch == "i386":
        return "i386"
    if arch == "arm64":
        return "arm64"
    if arch == "arm":
        return "arm32"
    return arch


class BuildMode(Enum):
    exe = 1
    lib = 2
    dll = 3
    obj = 4


class Builder:
    proj: str
    collections: dict[str, str] = {}
    defines: dict[str, any] = {}
    output: str = "build"
    debug: bool = True
    os: str = host_os()
    arch: str = host_arch()
    mode: BuildMode = BuildMode.exe

    def target(self) -> str:
        return f"{self.os}_{self.arch}"

    def is_target_supported(self) -> bool:
        return self.target() in supported_targets

    def exe_extension(self) -> str:
        if self.os == "windows":
            return ".exe"
        return ""

    def lib_extension(self) -> str:
        if self.os == "windows":
            return ".lib"
        return ".a"

    def dll_extension(self) -> str:
        if self.os == "windows":
            return ".dll"
        elif self.os == "darwin":
            return ".dylib"
        return ".so"

    def obj_extension(self) -> str:
        if self.os == "windows":
            return ".obj"
        return ".o"

    def extension(self) -> str:
        match self.mode:
            case BuildMode.exe:
                return self.exe_extension()
            case BuildMode.lib:
                return self.lib_extension()
            case BuildMode.dll:
                return self.dll_extension()
            case BuildMode.obj:
                return self.obj_extension()

    def build(self):
        if not self.is_target_supported():
            print(f"Target {self.target()} is not supported.")
            return
        print(f"Building {self.proj}...")
        args = ["odin", "build", self.proj]
        for name, path in self.collections.items():
            args.append(f"-collection:{name}={path}")
        if self.debug:
            args.append("-debug")
        args.append(f"-target:{self.target()}")
        args.append(f"-out:{self.output}/{self.proj}{self.extension()}")
        args.append(f"-build-mode:{self.mode.name}")
        for define, value in self.defines.items():
            args.append(f"-define:{define}={value}")
        args.append("-vet")
        subprocess.run(args, check=True)

    def run(self):
        if self.mode == BuildMode.exe:
            print(f"Running {self.proj}...")
            subprocess.run(
                [f"./{self.output}/{self.proj}{self.extension()}"],
                check=True,
                cwd=self.output,
            )
        else:
            print(f"Cannot run a {self.mode.name}.")


def exists(path: str) -> bool:
    import os

    return os.path.exists(path)


def copy_file_if_not_exists(src: str, dst: str):
    import os

    if not exists(dst):
        shutil.copyfile(src, dst)
        os.fsync(dst)


def build_app(debug=False):
    shutil.copytree("assets", "build/assets", dirs_exist_ok=True)
    copy_file_if_not_exists(
        "external/slang/slang/bin/slang.dll",
        "build/slang.dll",
    )
    copy_file_if_not_exists(get_vendor_path("SDL2/SDL2.dll"), "build/SDL2.dll")

    # build("app", {"en": ".", "external": "external"}, debug=debug)
    opts = Builder()
    opts.proj = "app"
    opts.collections["en"] = "."
    opts.collections["external"] = "external"
    opts.debug = debug
    opts.build()
    return opts


def run_app(debug=False):
    # wait a second
    import time

    time.sleep(1)
    build_app(debug).run()


def clean():
    import os
    import shutil

    shutil.rmtree("build", ignore_errors=True)
    os.makedirs("build")


def main():
    # set cwd to the directory of this file
    import os

    os.chdir(os.path.dirname(os.path.realpath(__file__)))

    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["build", "run", "clean"])
    parser.add_argument("-debug", action="store_true")

    args = parser.parse_args()

    if args.command == "build":
        build_app(args.debug)
    elif args.command == "run":
        run_app(args.debug)
    elif args.command == "clean":
        clean()


if __name__ == "__main__":
    main()
