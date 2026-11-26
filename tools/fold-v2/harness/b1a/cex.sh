#!/bin/bash
# usage: cex.sh <log> : action trail + final key vars of a TLC counterexample
L=$1
/usr/bin/grep -n '^State [0-9]*:' $L | sed -E 's/^[0-9]+:State ([0-9]+): <([A-Za-z]+)( line [0-9]+)?.*/\1:\2/' | tr '\n' ' '; echo
last=$(/usr/bin/grep -n '^State [0-9]*:' $L | tail -1 | cut -d: -f1)
tail -n +$last $L | /usr/bin/grep -v '^$' | head -${2:-80}
