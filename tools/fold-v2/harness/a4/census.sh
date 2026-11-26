#!/bin/bash
# writable non-TLS data objects of the SERVER_MODE objects named by basename in $2 (one per line)
# usage: census.sh <build_preset dir> <names file>
D="${1:?build dir}/cubrid/CMakeFiles/cubrid.dir"
while read -r n; do
  find "$D" -name "$n.o" | while read -r o; do
  { readelf -SW "$o" | sed -n 's/^ *\[ *\([0-9]*\)\] \([^ ]*\) .*/S \1 \2/p'; readelf -sW "$o"; } | awk -v f="$n" '
    $1 == "S" { sec[$2] = $3; next }
    $4 == "OBJECT" && $7 ~ /^[0-9]+$/ && sec[$7] ~ /^\.(data|bss)/ && sec[$7] !~ /rel\.ro/ { print f "\t" $5 "\t" $8 }'
  done
done < "$2" | c++filt | sort -u
