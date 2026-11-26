#!/bin/bash
# reachable-state check of IndInv at small bounds, on a copy of the spec (quick feedback while Apalache iterates)
R=/home/cubrid/dev/workspace; B=$R/.git_ignored_dir/scratch/fold-v2/b1a/probe
tools=$R/.git_ignored_dir/tla/tools; jar=$tools/share/java/tla2tools.jar
java="$(/usr/bin/grep -o '/nix/store/[^" ]*/bin/java' "$tools/bin/tlc" | head -1)"
cp $R/docs/tla/CBRD-27430-B1a/Handoff.tla $B/
INVS=$(awk '/^IndInv ==/{f=1;next} f&&/^  \/\\ Inv[0-9]+$/{printf "%s ", $2} f&&/^$/{exit}' $B/Handoff.tla)
cat > $B/Reach.cfg <<CFG
SPECIFICATION Spec
CONSTANTS J = 2  MaxSlots = 1  NT = 1  MaxConn = 3  MaxCrash = 1  MaxRestart = 1  MaxTimeout = ${TO:-0}  MaxCancel = ${CN:-0}  HasStop = ${ST:-FALSE}  Mutant = "none"
INVARIANTS $INVS
CFG
cd $B && timeout ${T:-900} /usr/bin/env -u LD_LIBRARY_PATH -u JAVA_HOME -u CLASSPATH -u JAVA_TOOL_OPTIONS $java -XX:+UseParallelGC -Xmx16g -Djava.io.tmpdir=$B/jtmp -cp $jar tlc2.TLC -config Reach.cfg -metadir $B/meta -cleanup -noGenerateSpecTE -workers ${W:-6} Handoff.tla > $B/reach.log 2>&1
/usr/bin/grep -E 'is violated|states generated|No error|Error:|rror' $B/reach.log | head -5
