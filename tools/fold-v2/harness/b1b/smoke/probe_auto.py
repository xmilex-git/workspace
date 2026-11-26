#!/usr/bin/env python3
"""probe_auto.py <broker_port> <db> <user> <passwd> <adopt_socket> <broker_name> <jar> <javadir>
raw-wire checks of AUTO detach/resume:
 1. connect, commit (the session is idle), a second client connects: this connection is closed by the yield
 2. resume with a wrong password is refused and leaves the session kept
 3. resume with a wrong secret is refused
 4. resume with the right secret and password answers the same session id
 5. RESET on the control channel yields the idle session
"""
import socket, struct, subprocess, sys, time
sys.path.insert(0, sys.argv[0].rsplit("/", 1)[0] + "/../../b1a/smoke")
import probe_direct as pd

port, db, user, pw, adopt, broker, jar, javadir = sys.argv[1:9]
port = int(port)
resume_blob = bytes.fromhex(sys.argv[9]) if len(sys.argv) > 9 else None

def die(m):
    print("PROBE FAIL: " + m); sys.exit(1)

def connect(session=None, passwd=pw, expect_ok=True):
    s = socket.create_connection(("127.0.0.1", port), timeout=90)
    s.sendall(pd.connect_header())
    if struct.unpack(">i", pd.recv_exact(s, 4, "ack"))[0] != 0:
        die("ack")
    info = bytearray(pd.db_info(db, user, passwd))
    if session is not None:
        info[608:628] = session
    s.sendall(bytes(info))
    length = struct.unpack(">i", pd.recv_exact(s, 4, "len"))[0]
    pd.recv_exact(s, 4, "cas_info")
    body = pd.recv_exact(s, length, "body")
    if length == 36:
        if not expect_ok:
            die("connect was accepted")
        return s, body[16:36]
    code = struct.unpack(">i", body[4:8])[0]
    if expect_ok:
        die("connect refused: %d %r" % (code, body[8:]))
    s.close()
    return None, code

def commit(s):
    body = struct.pack(">b", 1) + struct.pack(">i", 1) + struct.pack(">b", 1)   # END_TRAN, CCI_TRAN_COMMIT
    s.sendall(struct.pack(">i", len(body)) + b"\x00\xff\xff\xff" + body)
    length = struct.unpack(">i", pd.recv_exact(s, 4, "len"))[0]
    pd.recv_exact(s, 4, "cas_info")
    pd.recv_exact(s, length, "body")

def closed_within(s, secs):
    s.settimeout(secs)
    try:
        return s.recv(1) == b""
    except socket.timeout:
        return False

def other_client():
    r = subprocess.run(["java", "-cp", javadir + ":" + jar, "B1bJdbc", str(port), db, "one"], capture_output=True, text=True)
    if r.returncode != 0:
        die("the second client failed: " + r.stdout[-300:] + r.stderr[-300:])

if resume_blob is not None:
    # after the broker restart: the session the reset yielded is still its client's
    s, blob = connect(resume_blob)
    if blob != resume_blob:
        die("after the reset the connection got another session")
    s.close()
    print("PROBE: resumed after the reset")
    print("PROBE: SUCCESS")
    sys.exit(0)

s, blob = connect()
if blob[12:20] == b"\x00" * 8:
    die("an AUTO session was given no secret")
commit(s)
other_client()
if not closed_within(s, 5):
    die("the idle session was not yielded")
print("PROBE: yielded by a second client")

_, code = connect(blob, passwd="wrong", expect_ok=False)
print("PROBE: resume with a wrong password refused (%d)" % code)
bad = bytearray(blob); bad[19] ^= 0x5A
_, code = connect(bytes(bad), expect_ok=False)
print("PROBE: resume with a wrong secret refused (%d)" % code)
s, blob2 = connect(blob)
if blob2 != blob:
    die("the resumed connection got another session: %r vs %r" % (blob2, blob))
print("PROBE: resumed the same session %d" % struct.unpack(">I", blob[8:12])[0])
commit(s)

# RESET on a control channel of the broker's name
MAGIC = 0x41444F50
c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); c.connect(adopt)
name = broker.encode().ljust(32, b"\x00")
c.sendall(struct.pack("<III", MAGIC, 1, 36) + struct.pack("<I", 1) + name)   # HELLO
pd.recv_exact(c, 12 + 4, "hello ack")
c.sendall(struct.pack("<III", MAGIC, 8, 0))                                    # RESET
if not closed_within(s, 5):
    die("the idle session was not yielded by the reset")
print("PROBE: yielded by a reset")
c.close()
print("BLOB " + blob.hex())
print("PROBE: SUCCESS")
