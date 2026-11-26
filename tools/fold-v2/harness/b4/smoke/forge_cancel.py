#!/usr/bin/env python3
"""forge_cancel.py <broker port> <token> <mode> [session id]: a query cancel ("QC") written by hand.
mode: nosid (no session id), sid (with the given session id). Prints the broker's reply code."""
import socket, struct, sys
port, token, mode = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
flag = 0x10 if mode == "sid" else 0
s = socket.create_connection(("127.0.0.1", port), timeout=20)
s.sendall(b"QC" + struct.pack(">IH", token, 0) + bytes([flag, 0]))
if mode == "sid":
    s.sendall(struct.pack(">I", int(sys.argv[4])))
r = b""
while len(r) < 4:
    c = s.recv(4 - len(r))
    if not c: break
    r += c
print("REPLY", struct.unpack(">i", r)[0] if len(r) == 4 else "short")
