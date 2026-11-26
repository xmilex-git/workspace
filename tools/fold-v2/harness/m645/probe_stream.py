#!/usr/bin/env python3
"""probe_stream.py <broker_port> <db> <user> <passwd>
A driver's STREAM_INIT / STREAM_READ_OPEN on a folded session is refused with an error reply, the connection
stays, and the next request (GET_DB_VERSION, then COMMIT) is answered."""
import struct, sys
sys.path.insert(0, sys.argv[0].rsplit("/", 2)[0] + "/b1a/smoke")
import probe_direct as pd

port, db, user, pw = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
s = pd.open_and_connect(port, db, user, pw)
pd.read_connect_reply(s)

def arg(b):
    return struct.pack(">i", len(b)) + b

def request(body, what):
    s.sendall(struct.pack(">i", len(body)) + b"\x00\xff\xff\xff" + body)
    length = struct.unpack(">i", pd.recv_exact(s, 4, what + " len"))[0]
    info = pd.recv_exact(s, 4, what + " cas_info")
    return info, pd.recv_exact(s, length, what + " body")

def refused(what, body):
    info, reply = request(body, what)
    ind, code = struct.unpack(">ii", reply[0:8])
    print("PROBE: %s -> indicator %d code %d msg %r cas_info %s" % (what, ind, code, reply[8:].rstrip(b"\x00")[:80], info.hex()))
    if ind >= 0:
        pd.die(what + " was not refused")

# kind 5 = debug echo upload, 6 = debug echo download
refused("stream_init", struct.pack(">b", 47) + arg(struct.pack(">i", 5)) + arg(b"") + arg(b"\x00") + arg(b""))
refused("stream_send_data", struct.pack(">b", 45) + arg(b"abc") + arg(b"\x00"))
refused("stream_read_open", struct.pack(">b", 49) + arg(struct.pack(">i", 6)) + arg(b"") + arg(struct.pack(">i", 0)) + arg(b"\x00"))
info, reply = request(struct.pack(">b", 15) + struct.pack(">i", 1) + struct.pack(">b", 0), "get_db_version")
if struct.unpack(">i", reply[0:4])[0] < 0:
    pd.die("get_db_version after the refusals answered an error")
info, reply = request(struct.pack(">b", 1) + arg(b"\x01"), "commit")
if struct.unpack(">i", reply[0:4])[0] < 0:
    pd.die("commit after the refusals answered an error")
print("PROBE: version and commit answered after the refusals, cas_info %s" % info.hex())
