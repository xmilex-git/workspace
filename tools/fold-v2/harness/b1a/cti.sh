#!/bin/bash
# show the newest Apalache CTI: states and the violated formula
d=$(ls -td /home/cubrid/dev/workspace/.git_ignored_dir/scratch/tla/CBRD-27430-B1a-* | head -1)
f=$(ls -t $(find $d -name 'violation1.tla') | head -1)
echo "$f"
/usr/bin/grep -n -E '^State[0-9]|^\(\* Transition|^InvariantViolation' "$f"
sed -n '/^InvariantViolation/,/^====/p' "$f"
