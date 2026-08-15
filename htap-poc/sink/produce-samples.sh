#!/usr/bin/env bash
# Manually produce the sample events (samples/*.jsonl, key<TAB>value) into
# the per-table topics via the kafka container's console producer.
# Re-running is the duplicate-redelivery test: same _version + same content
# must not change the canonical views (at-least-once, ADR 0004).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

produce () { # $1=topic $2=file
    podman exec -i htap-kafka /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$1" \
        --property parse.key=true --property key.separator=$'\t' \
        < "$HERE/samples/$2"
    echo "produced: $2 -> $1"
}

produce htapcdc.htapdb.t_order t_order.jsonl
produce htapcdc.htapdb.t_item  t_item.jsonl
