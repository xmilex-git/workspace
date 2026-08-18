#!/usr/bin/env bash
# Build debezium-connector-cubrid from the fork worktree (branch cubrid-connector)
# and land the self-contained plugin jar set into the Connect plugin mount.
# After this: podman restart htap-connect
set -euo pipefail

DEBEZIUM_SRC="${DEBEZIUM_SRC:-$HOME/htap-cdc/debezium}"
TOOLS="$HOME/htap-cdc/tools"
# always the pinned JDK 21 — an inherited JAVA_HOME (system JDK 8) breaks the build
export JAVA_HOME="$TOOLS/jdk-21.0.12+8"
export PATH="$TOOLS/apache-maven-3.9.16/bin:$JAVA_HOME/bin:$PATH"

HTAP_DATA="${HTAP_DATA:-$HOME/htap-data}"
PLUGIN_DIR="$HTAP_DATA/connect-plugins/debezium-connector-cubrid"
# host-install driver (ADR 0005 D7) — the isolated 11.5 install ships no jdbc/
JDBC_JAR="${CUBRID_JDBC_JAR:-$HOME/CUBRID/jdbc/cubrid-jdbc-11.3.2.0058.jar}"

mvn -q install:install-file -Dfile="$JDBC_JAR" \
    -DgroupId=cubrid -DartifactId=cubrid-jdbc -Dversion=11.3.2.0058 -Dpackaging=jar

# 3.7 split core into several modules — let Maven resolve the runtime jar set
# instead of hardcoding it (slf4j excluded: the Connect runtime provides it)
( cd "$DEBEZIUM_SRC/debezium-connector-cubrid" &&
  mvn -q package dependency:copy-dependencies -DincludeScope=runtime -DoutputDirectory=target/deps \
      -DskipTests -DskipITs -Dcheckstyle.skip -Dformat.skip -Drevapi.skip -Denforcer.skip )

mkdir -p "$PLUGIN_DIR" 2>/dev/null || true
# the :U volume mount rootless-chowns the dir to the container UID — write
# through the user namespace (same reason #34 needs `podman unshare rm`)
podman unshare bash -c "rm -f '$PLUGIN_DIR'/*.jar"
podman unshare cp \
   "$DEBEZIUM_SRC"/debezium-connector-cubrid/target/debezium-connector-cubrid-*-SNAPSHOT.jar \
   "$PLUGIN_DIR/"
for jar in "$DEBEZIUM_SRC"/debezium-connector-cubrid/target/deps/*.jar; do
    case "$jar" in *slf4j*) continue ;; esac
    podman unshare cp "$jar" "$PLUGIN_DIR/"
done

echo "plugin dir populated:"
podman unshare ls -1 "$PLUGIN_DIR"
echo "-> podman restart htap-connect (to reload the plugin)"
