#!/bin/bash
# list defined, non-TLS objects in writable sections (.data*/.bss*) of the SERVER_MODE parser objects
# usage: shared-writable.sh <build_preset dir>
D="${1:?build dir}/cubrid/CMakeFiles/cubrid.dir/__"
for o in "$D"/csql_grammar.c.o "$D"/csql_lexer.c.o "$D"/src/parser/*.o; do
  f=$(basename "$o" .o)
  { readelf -SW "$o" | sed -n 's/^ *\[ *\([0-9]*\)\] \([^ ]*\) .*/S \1 \2/p'; readelf -sW "$o"; } | awk -v f="$f" '
    $1 == "S" { sec[$2] = $3; next }
    $4 == "OBJECT" && $7 ~ /^[0-9]+$/ && sec[$7] ~ /^\.(data|bss)/ && sec[$7] !~ /rel\.ro/ { print f "\t" $8 }'
done | c++filt | sort
