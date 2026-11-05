# Pinned TLA+ toolchain for tools/tla/tla-check: tla2tools 1.8.0 (SANY, the PlusCal translator, TLC) with the
# JDK its wrappers exec, and the TLA+ Proof System tlapm 1.6.0-pre with its bundled back ends (Isabelle2025,
# LS4 for PTL, Z3, Zenon), the release build re-linked for this host in tlapm-next.nix (ADR 0045).
# `just tla-install` builds this into the GC root .git_ignored_dir/tla/tools.
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/c7def046b9a883d46974757852106483d741586f.tar.gz";
    sha256 = "0vplppav4izj2462i00a3vd0nbvaj6dbp4m582ndfhhnf8688579";
  };
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
  tlapm = import ./tlapm-next.nix;
in
pkgs.buildEnv {
  name = "tla-tools";
  paths = [
    pkgs.tlaplus18
    tlapm
  ];
}
