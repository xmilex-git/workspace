# Pinned toolchain for the tla-visualize skill: the pele Mermaid renderer (npm 1.13.0, the latest release on
# 2026-11-10), the Node that runs its build-time syntax check, the three faces of the page (Pretendard,
# Inter Tight, JetBrains Mono) and fonttools, which subsets them to the glyphs a page uses.
# `just tla-visualize-install` builds this into the GC root .git_ignored_dir/tla-visualize/tools.
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/c7def046b9a883d46974757852106483d741586f.tar.gz";
    sha256 = "0vplppav4izj2462i00a3vd0nbvaj6dbp4m582ndfhhnf8688579";
  };
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
  pele = pkgs.fetchurl {
    url = "https://registry.npmjs.org/pele/-/pele-1.13.0.tgz";
    hash = "sha512-Ie8UKY9x00MsuR3jO6AzUwzK2Z6MIV3Tf4EDdITiuk8Uaz8K7g0R082WqsqNaSU8DdgkrRvZThzhit83mi/uiw==";
  };
  # one file of google/fonts at a pinned commit: the google-fonts package fetches the whole repository (gigabytes)
  interTight = pkgs.fetchurl {
    name = "InterTight-wght.ttf";
    url = "https://raw.githubusercontent.com/google/fonts/0b58fb370093f9a9f4ff785d94405710b79de67c/ofl/intertight/InterTight%5Bwght%5D.ttf";
    hash = "sha256-uBtz3LZN88IwyrreffbFdzv4YyM/JMnuUQh1GfH4i28=";
  };
  python = pkgs.python3.withPackages (ps: [
    ps.fonttools
    ps.brotli
  ]);
in
pkgs.runCommand "tla-visualize-tools" { } ''
  mkdir -p $out/bin $out/lib/pele $out/share/fonts
  ln -s ${pkgs.nodejs_24}/bin/node $out/bin/node
  ln -s ${python}/bin/pyftsubset $out/bin/pyftsubset
  ln -s ${python}/bin/python3 $out/bin/python3
  tar -xzf ${pele} -C $out/lib/pele --strip-components=1
  for w in Regular Medium SemiBold Bold; do cp ${pkgs.pretendard}/share/fonts/opentype/Pretendard-$w.otf $out/share/fonts/; done
  cp ${interTight} $out/share/fonts/InterTight-wght.ttf
  cp '${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono[wght].ttf' $out/share/fonts/JetBrainsMono-wght.ttf
''
