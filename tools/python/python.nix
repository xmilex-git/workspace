# Pinned interpreter for this tooling repo's .venv: the newest CPython nixpkgs ships prebuilt
# (Rocky 8's dnf stops at 3.12). `just python-venv` builds it into the GC root
# .git_ignored_dir/python/interpreter and creates .venv from it.
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/e62746b0b472753ef019baceab6f1e2e52014980.tar.gz";
    sha256 = "010xm16sbwwh5jlhj3p79avsiy8qx85bk2kjyg4kgb46spvmy7dk";
  };
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
in
pkgs.python315
