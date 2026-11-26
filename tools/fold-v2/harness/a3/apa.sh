#!/bin/bash
# rerun only the Apalache inductive cfg of the A3 spec and print its counterexample, if any
cd /home/cubrid/dev/workspace
timeout 600 tools/tla/tla-check --only 'FoldBoundary.apalache-indinv' docs/tla/CBRD-27430-A3 2>&1 | /usr/bin/grep -E 'apalache-indinv expect' | cut -c1-120
d=$(ls -td .git_ignored_dir/scratch/tla/CBRD-27430-A3-*/ | head -1); v=$(find $d -name violation.tla | head -1)
[ -n "$v" ] && { sed -n '/InvariantViolation ==/,$p' $v | head -8; sed -n '/State0 ==/,/State1/p' $v | tr -s ' ' | tr '\n' ' ' | cut -c1-1300; echo; grep -o '_transition([0-9]*)' $v; }
