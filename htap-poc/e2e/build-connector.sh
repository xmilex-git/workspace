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

( cd "$DEBEZIUM_SRC/debezium-connector-cubrid" &&
  mvn -q package -DskipTests -DskipITs -Dcheckstyle.skip -Dformat.skip -Drevapi.skip -Denforcer.skip )

M2="$HOME/.m2/repository"
mkdir -p "$PLUGIN_DIR" 2>/dev/null || true
# the :U volume mount rootless-chowns the dir to the container UID — write
# through the user namespace (same reason #34 needs `podman unshare rm`)
podman unshare cp \
   "$DEBEZIUM_SRC/debezium-connector-cubrid/target/debezium-connector-cubrid-3.0.0.Final.jar" \
   "$M2/io/debezium/debezium-core/3.0.0.Final/debezium-core-3.0.0.Final.jar" \
   "$M2/io/debezium/debezium-api/3.0.0.Final/debezium-api-3.0.0.Final.jar" \
   "$M2/net/java/dev/jna/jna/5.14.0/jna-5.14.0.jar" \
   "$JDBC_JAR" \
   "$PLUGIN_DIR/"

echo "plugin dir populated:"
podman unshare ls -1 "$PLUGIN_DIR"
echo "-> podman restart htap-connect (to reload the plugin)"
