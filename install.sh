#!/usr/bin/env bash
#
# Installs ida_kernelcache_ng as an IDA plugin for IDA 9.x on macOS.
#
# IDA 9 no longer bundles Python: it loads the interpreter selected by idapyswitch
# and adds $IDAUSR/python (default ~/.idapro/python) to sys.path, as controlled by
# IDAPYTHON_IDAUSR_SYSPATH in cfg/idapython.cfg (default YES; the directory is only
# added if it exists). The "python" location itself is an IDA 9.0 change: 7.7-8.4
# added $IDAUSR/python/<major>, i.e. ~/.idapro/python/3.
# Linking the pure-Python package there means this script never needs to know which
# Python IDA is using.
#
# Overrides:
#   IDAUSR   IDA user directory (default: ~/.idapro)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IDAUSR="${IDAUSR:-$HOME/.idapro}"
PLUGIN_NAME="ida_kernelcache_develop.py"

log() { printf '[ida_kernelcache_ng] %s\n' "$*"; }
die() { printf '[ida_kernelcache_ng] error: %s\n' "$*" >&2; exit 1; }

install_package() {
    local target="$IDAUSR/python"

    mkdir -p "$target"
    # Link instead of copy: edits are picked up without reinstalling, and
    # pac_symbolicate.py walks up three levels from phases/pac_symbolicate.py to
    # $IDAUSR/python looking for symdb.json, so that file must be linked there too.
    rm -rf "$target/ida_kernelcache" "$target/symdb.json"
    ln -s "$SCRIPT_DIR/ida_kernelcache" "$target/ida_kernelcache"
    ln -s "$SCRIPT_DIR/symdb.json" "$target/symdb.json"

    [[ -f "$target/ida_kernelcache/__init__.py" && -f "$target/symdb.json" ]] ||
        die "failed to link the package into $target"
    log "Linked package into $target"
}

install_plugin_stub() {
    local plugin_dir="$IDAUSR/plugins"

    mkdir -p "$plugin_dir"
    install -m 0644 "$SCRIPT_DIR/ida_plugin_stub.py" "$plugin_dir/$PLUGIN_NAME"
    log "Installed plugin stub at $plugin_dir/$PLUGIN_NAME"
}

main() {
    install_package
    install_plugin_stub
    log "Done. Restart IDA and run \"IDA KernelCache NG\" from the Edit > Plugins menu on an ARM64 kernelcache."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
