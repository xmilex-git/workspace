#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — pinned harness
configuration.

IMPL-SSOT.md section 8-b (AMEND-E) requires the inherited `tpch-sspq/harness/`
to be copied into a campaign-local checked-in copy and adapted, because the
inherited copy is hardcoded to the previous measurement campaign
`tpch-sspq-fk-r1-20260730`. Rather than scattering the corrected constants
across ten files (which is how the inherited copy drifted in the first place),
every campaign-specific value lives HERE and the adapted files import it. A
future amendment to the contract changes one file, not ten.

Every value below is quoted from the pinned IMPL-SSOT blob
`1118b18ff1718f8493d72921fb7bb8851e6a1d8c` at commit
`ed6fb39f4ea39218b1a8243562083401678a2723`, with the section that fixes it.
"""
import hashlib
import os
import subprocess

# --- identity, section 1-c ---------------------------------------------------
CAMPAIGN = "tpch-sspq-impl-r1-20260803"
RAW_ROOT = f"/data/tpch-sspq/{CAMPAIGN}"

# Pin history. The pinned blob advanced mid-run when the controller committed
# AMEND-F; the re-pin was escalated (section 11-a) and approved by the user. It is
# a bookkeeping re-pin: every section governing Phase 1A — 3, 6, 7, 8, 9 — is
# byte-identical across the two blobs, proven by hashing each top-level section of
# both independently. The evidence lives in
# {RAW_ROOT}/work/BASELINE/repin-record.json.
#
# Both pins are kept rather than the record being flattened to the final one: the
# blocks collected before the amendment genuinely carry the start pin in their own
# artifacts, and a single-pin record would misrepresent that.
IMPL_SSOT_COMMIT_AT_START = "ed6fb39f4ea39218b1a8243562083401678a2723"
IMPL_SSOT_BLOB_AT_START = "1118b18ff1718f8493d72921fb7bb8851e6a1d8c"
# AMEND-G. The fast Phase 1A sweep (section 3-c-1) runs under THIS pin, which is
# the pin that describes it: the amendment was committed and proved reachable from
# origin/main BEFORE the sweep started. The two pins above belong to the abandoned
# restart-regime run whose evidence now lives in raw-restart-calibration/.
IMPL_SSOT_COMMIT_RESTART_REGIME = "2de2404ba3e39016c423a85900e5b04a39dfda14"
IMPL_SSOT_BLOB_RESTART_REGIME = "111c281081785cd25f2b59d74b2a38dfaa75d7da"
IMPL_SSOT_COMMIT = "eccdd1ae58cd733ed3121585146d68b9ae54a73f"
IMPL_SSOT_BLOB = "15b42ddca521444fa54b34b0fa8477ed2df643f6"
CUBRID_BASE_SHA = "607f1ee9fb2394de129e083602c84a6525fc685c"

# Section 6-a: the immutable base binary's recorded fingerprint. Asserted before
# the sweep starts so a rebuilt or swapped install/base is a stop-and-report
# condition rather than a silently different B.
BASE_CUB_SERVER_SHA256 = (
    "16abc26afa1db16992b6213ecc02adc193d674eb8ba91f0963ae414abd953199")

# --- install prefixes, section 6-a-1 -----------------------------------------
# The previous campaign's install /home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9
# and the ~/CUBRID symlink are FORBIDDEN as this campaign's B.
CAMPAIGN_ROOT = "/home/cubrid/dev/tpch-sspq-impl-r1"
VARIANT = os.environ.get("TPCH_SSPQ_IMPL_VARIANT", "base")
CUBRID_HOME = os.environ.get(
    "TPCH_SSPQ_IMPL_PREFIX", os.path.join(CAMPAIGN_ROOT, "install", VARIANT))
FORBIDDEN_PREFIXES = (
    "/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9",
    "/home/cubrid/CUBRID",
)

# --- runtime configuration pin, section 6-a-2 --------------------------------
CONF_SHA256 = "ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff"
CANONICAL_CONF_SOURCE = (
    "/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/conf/cubrid.conf")
# Deliberately campaign-wide, NOT per-IMP: cub_master binds
# ${CUBRID_TMP}/CUBRID<port>, so the master socket path must be stable for the
# whole campaign. Section 6-a-2 names this the only permitted exception to the
# work/<IMP-ID> rule of section 8-e. Never /tmp, never $TMPDIR.
CUBRID_TMP = f"{RAW_ROOT}/work/tmp"

# --- database, section 3-b ---------------------------------------------------
CUBRID_DB = "tpch_sf10_q1"
CUBRID_DATABASES = (
    "/home/cubrid/dev/workspace/.git_ignored_dir/tpch-sspq/cubrid-databases")
CUBRID_PORT = 1523

# --- CPU / NUMA contract, section 3-a ----------------------------------------
SUT_CPUS = "0-15"
SUT_CPU_SET = set(range(0, 16))
COLLECTOR_CPUS = "20-23"
COLLECTOR_CPU_SET = {20, 21, 22, 23}
MEMBIND_NODE = "0"
# AMEND-D: 6.0 core-s/s, decided by measurement on this host, NOT inherited.
# The adapted shell scripts read this value rather than carrying their own
# literal, so a future amendment cannot be silently ignored by a stale constant.
EXTERNAL_LOAD_THRESHOLD = 6.0

# --- block regime, sections 3-c / 6-c / 6-d ----------------------------------
N_MEASURED = 3            # 6-c: 1 uncounted warmup + 3 measured runs
N_BLOCKS = 6              # 6-d: 3 pairs => 6 block medians per variant
TIMEOUT = 300             # 3-c

# --- repo paths --------------------------------------------------------------
REPO = "/home/cubrid/dev/workspace/tpch-sspq"
QUERIES = os.path.join(REPO, "queries")
HARNESS = os.path.dirname(os.path.abspath(__file__))

# PostgreSQL is NOT on this campaign's Phase 1A measurement path (section 3-d:
# environment sentinel only). The constants exist solely so the inherited
# process-discovery code keeps compiling; no Phase 1A block runs PostgreSQL.
PG_HOME = "/home/cubrid/pg/pg20devel-5713b437"
PG_SOCKDIR = "/home/cubrid/pg/pgdata-tpch-sspq"
PG_PORT = "5442"
PG_DB = "tpch_sspq"
PG_USER = "cubrid"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def assert_cubrid_tmp():
    """Section 6-a-2: mandatory pre-run assertion. A block run with
    CUBRID_TMP=/tmp is INVALID."""
    v = os.environ.get("CUBRID_TMP")
    if v != CUBRID_TMP:
        raise SystemExit(
            f"FATAL CUBRID_TMP={v!r} but section 6-a-2 pins {CUBRID_TMP!r}")
    if not os.path.isdir(v):
        raise SystemExit(f"FATAL campaign temp dir {v!r} does not exist")
    return v


def assert_conf_sha(prefix=None):
    """Section 6-a-2: sha256sum <prefix>/conf/cubrid.conf MUST equal the pinned
    value before EVERY measurement block, and the value MUST be recorded."""
    prefix = prefix or CUBRID_HOME
    path = os.path.join(prefix, "conf", "cubrid.conf")
    got = sha256_file(path)
    if got != CONF_SHA256:
        raise SystemExit(
            f"FATAL {path} sha256 {got} != pinned {CONF_SHA256} (section 6-a-2)")
    return got


def assert_prefix_allowed(prefix=None):
    """Section 6-a-1: the previous campaign's install and ~/CUBRID are forbidden
    as this campaign's base binary."""
    prefix = prefix or CUBRID_HOME
    real = os.path.realpath(prefix)
    for bad in FORBIDDEN_PREFIXES:
        if real == os.path.realpath(bad):
            raise SystemExit(
                f"FATAL install prefix {prefix!r} resolves to the forbidden "
                f"{bad!r} (section 6-a-1)")
    if not real.startswith(os.path.join(CAMPAIGN_ROOT, "install")):
        raise SystemExit(
            f"FATAL install prefix {real!r} is not under "
            f"{CAMPAIGN_ROOT}/install (section 3-b)")
    return real


def binary_fingerprint(prefix=None):
    """Section 6-a: record binary SHA-256 and ELF Build ID for every variant."""
    prefix = prefix or CUBRID_HOME
    out = {}
    for name in ("cub_server", "cub_master", "csql"):
        p = os.path.join(prefix, "bin", name)
        bid = None
        r = subprocess.run(["readelf", "-n", p], capture_output=True, text=True)
        for line in r.stdout.split("\n"):
            if "Build ID:" in line:
                bid = line.split("Build ID:")[1].strip()
                break
        out[name] = {"path": p, "sha256": sha256_file(p), "build_id": bid}
    return out


def campaign_env():
    """The pinned client environment for every campaign client process."""
    env = dict(os.environ)
    env["CUBRID"] = CUBRID_HOME
    env["CUBRID_DATABASES"] = CUBRID_DATABASES
    env["CUBRID_TMP"] = CUBRID_TMP
    env["LD_LIBRARY_PATH"] = f"{CUBRID_HOME}/lib:{CUBRID_HOME}/cci/lib"
    return env


# Every module that imports this config inherits the pinned temp directory, so
# no adapted file can fall back to the inherited `/tmp`.
os.environ["CUBRID_TMP"] = CUBRID_TMP
