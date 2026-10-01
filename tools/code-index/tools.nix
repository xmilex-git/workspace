# Pinned toolchain for tools/code-index (decisions D12, D13): Universal Ctags, GNU Global and the
# python3 that runs code_index.py, all from one nixpkgs revision so the acceptance-tested versions
# stay fixed. `just code-index-install` builds this into the GC root .git_ignored_dir/code-index/tools.
# nixpkgs' global already pulls python3 (for its pygments plug-in, which code-index never uses), so
# listing python3 here adds nothing to the closure.
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
pkgs.buildEnv {
  name = "code-index-tools";
  paths = [
    pkgs.universal-ctags
    pkgs.global
    pkgs.python3
  ];
}
