# TLAPS toolchain: the tlapm 1.6.0-pre release build (tlaplus/tlapm GitHub release "1.6.0-pre",
# asset fetched 2026-11-05), which bundles Isabelle/TLA+ (Poly/ML and the Pure and TLA+ heaps), LS4 with
# ptl_to_trp, Z3 and Zenon. The release binaries need glibc 2.38 and this host has 2.28, so they are
# re-linked against the pinned nixpkgs glibc (autoPatchelfHook). 1.6.0-pre is a rolling pre-release: the
# fixed-output hash pins the asset of that day, and the GC root keeps it after upstream replaces it.
# tools.nix includes it; `just tla-install` builds both into the GC root .git_ignored_dir/tla/tools (ADR 0045).
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/c7def046b9a883d46974757852106483d741586f.tar.gz";
    sha256 = "0vplppav4izj2462i00a3vd0nbvaj6dbp4m582ndfhhnf8688579";
  };
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
in
pkgs.stdenv.mkDerivation {
  pname = "tlapm";
  version = "1.6.0-pre-20261105";
  src = pkgs.fetchurl {
    url = "https://github.com/tlaplus/tlapm/releases/download/1.6.0-pre/tlapm-1.6.0-pre-x86_64-linux-gnu.tar.gz";
    sha256 = "13gfi8an5irn8sqhx7n9ihvv1p6lbvhaxnxwgnr6yd2225fy8mrk";
  };
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.zlib pkgs.gmp pkgs.stdenv.cc.cc.lib ];
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    mkdir -p $out
    cp -a bin lib doc $out/
  '';
}
