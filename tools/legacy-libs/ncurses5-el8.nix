# libncurses.so.5 / libtinfo.so.5 / libform.so.5 for the 10.2, 11.0 and 11.2 release installs, which Rocky 8
# lacks. nixpkgs' ncurses5 needs GLIBC_2.33+, so this unpacks Rocky 8.10's own ncurses-compat-libs (glibc 2.28).
# Build: nix-build tools/legacy-libs/ncurses5-el8.nix -o .git_ignored_dir/legacy-libs/ncurses5
# Use:   LD_LIBRARY_PATH=$CUBRID/lib:<that root>/lib64
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/c7def046b9a883d46974757852106483d741586f.tar.gz";
    sha256 = "0vplppav4izj2462i00a3vd0nbvaj6dbp4m582ndfhhnf8688579";
  };
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
  file = "ncurses-compat-libs-6.1-10.20180224.el8.x86_64.rpm";
  path = "8.10/BaseOS/x86_64/os/Packages/n/${file}";
in
pkgs.runCommand "ncurses5-el8" {
  src = pkgs.fetchurl {
    name = file;
    urls = [
      "https://dl.rockylinux.org/pub/rocky/${path}"
      "https://dl.rockylinux.org/vault/rocky/${path}"
    ];
    sha256 = "1qmar4ifsjqjxrj3axzmdgqall3npcp09hdsjfi0d1qq6k9adr13";
  };
  nativeBuildInputs = [ pkgs.libarchive ];
} ''
  mkdir -p $out
  bsdtar -xf $src -C $out ./usr/lib64
  mv $out/usr/lib64 $out/lib64
  rmdir $out/usr
''
