# Apalache, the symbolic model checker for TLA+ (SMT through its bundled Z3): the v0.62.4 release
# asset (apalache-mc/apalache GitHub release, fetched 2026-11-06), run on the pinned nixpkgs JDK 21.
# tla-check uses it for the bounded-free inductive check (`*.apalache-*.cfg`, cubrid-tla PROOFS.md).
# tools.nix includes it; `just tla-install` builds it into the GC root .git_ignored_dir/tla/tools.
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
  pname = "apalache";
  version = "0.62.4";
  src = pkgs.fetchurl {
    url = "https://github.com/apalache-mc/apalache/releases/download/v0.62.4/apalache-0.62.4.tgz";
    sha256 = "1x1fmb3jq56q1030r1bvrdjdqbnww4r06az0q95c3yijp8xvb0dp";
  };
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/bin $out/lib
    cp lib/apalache.jar $out/lib/
    cp bin/apalache-mc $out/lib/apalache-mc
    makeWrapper $out/lib/apalache-mc $out/bin/apalache-mc --prefix PATH : ${pkgs.jdk21_headless}/bin \
      --set APALACHE_JAR $out/lib/apalache.jar --unset LD_LIBRARY_PATH
  '';
}
