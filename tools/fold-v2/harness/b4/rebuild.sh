#!/bin/bash
# Rebuild the fold installs the 11-24 disk cleanup removed. usage: rebuild.sh fold|tla4
set -u
cd /home/cubrid/dev/workspace
L=.git_ignored_dir/scratch/fold-v2/b4
case "$1" in
fold)
  JOBS=8 INSTALL_PREFIX=$HOME/optdebug/CUBRID-cas-fold-v2 WORKSPACE=$HOME/dev/cubrid-worktree/cas-fold-v2 just build optdebug > $L/build-optdebug.log 2>&1
  echo "optdebug rc=$?"; tail -1 $L/build-optdebug.log
  JOBS=8 INSTALL_PREFIX=$HOME/release/CUBRID-cas-fold-v2 WORKSPACE=$HOME/dev/cubrid-worktree/cas-fold-v2 just build release > $L/build-release.log 2>&1
  echo "release rc=$?"; tail -1 $L/build-release.log
  ;;
tla4)
  JOBS=8 INSTALL_PREFIX=$HOME/optdebug/CUBRID-cas-fold-v2-tla4 WORKSPACE=$HOME/dev/cubrid-worktree/cas-fold-v2-tla4 just build optdebug > $L/build-tla4.log 2>&1
  echo "tla4 rc=$?"; tail -1 $L/build-tla4.log
  ;;
esac
for i in $HOME/optdebug/CUBRID-cas-fold-v2 $HOME/release/CUBRID-cas-fold-v2 $HOME/optdebug/CUBRID-cas-fold-v2-tla4; do [ -f $i/lib/libcubrid.so.11.5 ] && echo "$i $(sha256sum $i/lib/libcubrid.so.11.5 | cut -c1-12)"; done
