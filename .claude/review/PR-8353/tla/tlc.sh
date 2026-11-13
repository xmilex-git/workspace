#!/bin/bash
# usage: tlc.sh <cfg> <out>
cd /home/cubrid/dev/workspace/.git_ignored_dir/scratch/pr8353-tla
exec /usr/bin/env -u LD_LIBRARY_PATH -u JAVA_HOME JAVA_TOOL_OPTIONS=-Djava.io.tmpdir=$PWD/jtmp \
  tlc -workers 16 -metadir states/$(basename "$1" .cfg) -config "$1" PR8353.tla > "$2" 2>&1
