#!/usr/bin/env bash
#
# Installs ida_kernelcache_ng into the IDA Pro installation on this machine.
#
# Targets IDA 9.x on macOS (tested against IDA Professional 9.4). IDA 9 no longer
# bundles its own Python: idapyswitch stores the interpreter to use under the
# Python3TargetDLL value of IDA's registry, and that interpreter is what must
# receive the ida_kernelcache package.
#
# Overrides:
#   IDA_DIR      path to the IDA .app bundle (default: newest IDA found in /Applications)
#   IDAUSR       IDA user directory (default: ~/.idapro)
#   IDA_PYTHON   interpreter to install into (default: derived from Python3TargetDLL)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IDAUSR="${IDAUSR:-$HOME/.idapro}"
PLUGIN_NAME="ida_kernelcache_develop.py"

# Filled in by detect_ida / detect_python; keep values supplied by the environment.
: "${IDA_DIR:=}"
: "${IDA_PYTHON:=}"

log() { printf '[ida_kernelcache_ng] %s\n' "$*"; }
die() { printf '[ida_kernelcache_ng] error: %s\n' "$*" >&2; exit 1; }

detect_ida() {
    if [[ -n "${IDA_DIR:-}" ]]; then
        [[ -d "$IDA_DIR" ]] || die "IDA_DIR=\"$IDA_DIR\" is not a directory"
        log "Using IDA at $IDA_DIR (from IDA_DIR)"
        return
    fi

    local candidates=() candidate
    for candidate in "/Applications/IDA Professional "*.app \
                     "/Applications/IDA Pro "*.app \
                     "$HOME"/Applications/IDA*.app; do
        [[ -d "$candidate" ]] && candidates+=("$candidate")
    done
    ((${#candidates[@]})) || die "no IDA installation found; set IDA_DIR=/path/to/IDA.app"

    # Highest bundle version wins; version strings look like 9.4.260713.a97520e5.
    IDA_DIR=$(
        for candidate in "${candidates[@]}"; do
            version=$(defaults read "$candidate/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$version" "$candidate"
        done | sort -V -k1,1 | tail -n 1 | cut -f 2-
    )

    [[ -n "$IDA_DIR" ]] || die "could not determine IDA version; set IDA_DIR=/path/to/IDA.app"
    log "Detected IDA at $IDA_DIR"
}

# Prints the libpython path IDA is configured to use (set by idapyswitch).
read_python_dll() {
    local registry="$IDAUSR/ida.reg"
    [[ -f "$registry" ]] || return 1

    # IDA's registry format: "<key>\0<u32 length><u8 type><value>".
    perl -0777 -e '
        my ($path, $key) = @ARGV;
        open(my $fh, "<:raw", $path) or exit 1;
        local $/;
        my $data = <$fh>;
        if ($data =~ /\Q$key\E\x00(.{4})(.)(.*)/s) {
            my $length = unpack("V", $1);
            my $value = substr($3, 0, $length);
            $value =~ s/\x00.*//s;
            print $value;
        }
    ' "$registry" "Python3TargetDLL"
}

# Maps a libpython dylib to the matching python3 executable.
python_from_dll() {
    local dll="$1" dir candidate
    dir=$(dirname -- "$dll")

    # Framework layout: .../Versions/<x.y>/Python -> .../Versions/<x.y>/bin/python3
    if [[ "$dll" == */Versions/*/Python ]]; then
        candidate="$dir/bin/python3"
        [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    fi

    # libpython3.x.dylib layout: look for a sibling bin/ directory.
    for candidate in "$dir/bin/python3" "$dir/../bin/python3" "$dir/../python3"; do
        [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

detect_python() {
    if [[ -n "${IDA_PYTHON:-}" ]]; then
        [[ -x "$IDA_PYTHON" ]] || die "IDA_PYTHON=\"$IDA_PYTHON\" is not executable"
        log "Using Python: $IDA_PYTHON (from IDA_PYTHON)"
        return
    fi

    local dll=""
    if dll=$(read_python_dll) && [[ -n "$dll" ]]; then
        IDA_PYTHON=$(python_from_dll "$dll") ||
            die "IDA targets \"$dll\" but no python3 executable was found next to it; set IDA_PYTHON"
    else
        die "IDA has no Python configured (no Python3TargetDLL in $IDAUSR/ida.reg); run \"$IDA_DIR/Contents/MacOS/idapyswitch\" or set IDA_PYTHON"
    fi

    "$IDA_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' ||
        die "$IDA_PYTHON is older than Python 3.8, which IDA 9.x requires"

    log "Using Python: $IDA_PYTHON ($("$IDA_PYTHON" -c 'import platform; print(platform.python_version())') from IDA's idapyswitch selection)"
}

# Import check must not run from the repository directory: the package would be
# found on sys.path[0] even when the installation is broken.
python_can_import_package() {
    (cd / && "$IDA_PYTHON" -c 'import ida_kernelcache' 2>/dev/null)
}

install_python_package() {
    if python_can_import_package; then
        log "ida_kernelcache is already importable; refreshing editable install"
    fi

    local pip_args=(install --user -e "$SCRIPT_DIR")
    # Homebrew and python.org installs mark themselves externally managed (PEP 668);
    # --user keeps the install out of the interpreter's own directory.
    if "$IDA_PYTHON" -c 'import os, sysconfig; raise SystemExit(0 if os.path.exists(os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")) else 1)'; then
        pip_args+=(--break-system-packages)
    fi

    "$IDA_PYTHON" -m pip "${pip_args[@]}" ||
        die "pip install failed for $IDA_PYTHON"

    python_can_import_package ||
        die "ida_kernelcache is not importable by $IDA_PYTHON after installation"

    log "Installed ida_kernelcache (editable) for $IDA_PYTHON"
}

install_plugin_stub() {
    local plugin_dir="$IDAUSR/plugins"
    mkdir -p "$plugin_dir"
    install -m 0644 "$SCRIPT_DIR/ida_plugin_stub.py" "$plugin_dir/$PLUGIN_NAME"
    log "Installed plugin stub at $plugin_dir/$PLUGIN_NAME"
}

main() {
    detect_ida
    detect_python
    install_python_package
    install_plugin_stub

    log "Done. Restart IDA and run \"IDA KernelCache NG\" from the Edit > Plugins menu on an ARM64 kernelcache."
}

main "$@"
