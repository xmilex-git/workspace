# PROTOTYPE (#485, throwaway): rewrite a CUBRID develop _lgat as a sparse fresh log (R5 L1-L6).
# usage: fm485_proto.py hdr <lgat> | scan <vol>... | mklog <old_lgat> <new_lgat> <A|B> [extra_pages]
import struct, sys, os, zlib

H = 16  # LOG_HDRPAGE size; LOG_HEADER starts here
CDC_NONE = 0


def lsa_dec(b):
    v = struct.unpack('<q', b)[0]
    pageid = v & ((1 << 48) - 1)
    if pageid >= 1 << 47:
        pageid -= 1 << 48
    off = (v >> 48) & 0xFFFF
    if off >= 1 << 15:
        off -= 1 << 16
    return (pageid, off)


def lsa_enc(pageid, off):
    v = (pageid & ((1 << 48) - 1)) | ((off & 0xFFFF) << 48)
    return struct.pack('<Q', v)


NULL_LSA = lsa_enc(-1, -1)

FIELDS = [  # (name, off in LOG_HEADER, fmt)
    ('magic', 0, '25s'), ('db_creation', 32, '<q'), ('vol_creation', 40, '<q'), ('db_release', 48, '15s'),
    ('db_compat', 64, '<f'), ('iopagesize', 68, '<h'), ('logpagesize', 70, '<h'), ('is_shutdown', 72, 'B'),
    ('next_trid', 76, '<i'), ('mvcc_next_id', 80, '<Q'), ('npages', 96, '<i'), ('db_charset', 100, 'B'),
    ('was_copied', 101, 'B'), ('sysmeta', 102, '<H'), ('fpageid', 104, '<q'), ('append_lsa', 112, 'L'),
    ('chkpt_lsa', 120, 'L'), ('nxarv_pageid', 128, '<q'), ('nxarv_phy_pageid', 136, '<i'), ('nxarv_num', 140, '<i'),
    ('last_arv_sys', 144, '<i'), ('last_del_arv', 148, '<i'), ('prefix', 176, '18s'),
    ('vacuum_last_blockid', 200, '<q'), ('eof_lsa', 320, 'L'), ('smallest_lsa_chkpt', 328, 'L'),
    ('mvcc_op_log_lsa', 336, 'L'), ('oldest_visible', 344, '<Q'), ('newest_block_mvccid', 352, '<Q'),
]


def hdr(path):
    with open(path, 'rb') as f:
        p = f.read(16384)
    out = {}
    for n, o, fmt in FIELDS:
        b = p[H + o:]
        if fmt == 'L':
            out[n] = lsa_dec(b[:8])
        else:
            v = struct.unpack_from(fmt, b)[0]
            out[n] = v.split(b'\0')[0].decode() if isinstance(v, bytes) else v
    return out


def checksum(page, logpagesize):
    page = bytearray(page)
    page[12:16] = b'\0\0\0\0'
    buf = b''.join(page[i * 4096:i * 4096 + 16] + page[i * 4096 + 4080:i * 4096 + 4096]
                   for i in range(logpagesize // 4096))
    return struct.pack('<i', struct.unpack('<i', struct.pack('<I', zlib.crc32(buf)))[0])


def scan(vols):
    for v in vols:
        sz = os.path.getsize(v)
        with open(v, 'rb') as f:
            head = f.read(16384)
        iops = struct.unpack_from('<h', head, 58)[0]
        db_creation = struct.unpack_from('<q', head, 104)[0]
        print(f'{v}: iopagesize={iops} pages={sz // iops} db_creation={db_creation} '
              f'chkpt_lsa={lsa_dec(head[120:128])}')
        mx, mxat, n_nonnull, n_bad_wm = (-1, -1), None, 0, 0
        with open(v, 'rb') as f:
            pid = 0
            while True:
                pg = f.read(iops)
                if len(pg) < iops:
                    break
                l = lsa_dec(pg[0:8])
                if pg[0:8] != pg[-8:]:
                    n_bad_wm += 1
                if l[0] >= 0:
                    n_nonnull += 1
                    if l > mx:
                        mx, mxat = l, (pid, pg[14])
                pid += 1
        print(f'  max page lsa={mx} at (pageid, ptype)={mxat} non-null={n_nonnull} lsa!=watermark={n_bad_wm}')


def mklog(old, new, mode, extra):
    h = hdr(old)
    lps = h['logpagesize']
    with open(old, 'rb') as f:
        oldhdr = bytearray(f.read(lps))
    F = h['append_lsa'][0] + 1 + extra if mode == 'B' else 0
    npages_total = h['npages'] + 1
    p = bytearray(lps)
    p[0:8] = struct.pack('<q', -9)  # LOGPB_HEADER_PAGE_ID
    p[8:10] = struct.pack('<h', -1)
    a = bytearray(384)
    a[0:25] = b'CUBRID/LogActive'.ljust(25, b'\0')
    a[28:32] = struct.pack('<i', CDC_NONE)  # LOG_HDR_CDC_ARV_NUM_RESET
    a[32:40] = struct.pack('<q', h['db_creation'])  # keep: volumes untouched
    a[40:48] = struct.pack('<q', h['vol_creation'])
    a[48:63] = oldhdr[H + 48:H + 63]  # db_release of the producing engine (develop here)
    a[64:68] = oldhdr[H + 64:H + 68]  # db_compatibility
    a[68:72] = oldhdr[H + 68:H + 72]
    a[72] = 1
    a[76:80] = struct.pack('<i', 1)
    a[80:88] = struct.pack('<Q', h['mvcc_next_id'])
    a[88:96] = struct.pack('<ii', 100, 977)
    a[96:100] = struct.pack('<i', npages_total - 1)
    a[100] = h['db_charset']
    a[101] = 1  # was_copied
    a[102:104] = struct.pack('<H', 1)  # sysmeta_version
    a[104:112] = struct.pack('<q', F)
    a[112:120] = lsa_enc(F, 0)
    a[120:128] = lsa_enc(F, 0)
    a[128:136] = struct.pack('<q', F)
    a[136:140] = struct.pack('<i', 1)
    a[140:144] = struct.pack('<i', 0)
    a[144:152] = struct.pack('<ii', -1, -1)
    for o in (152, 160, 168, 320, 328, 336):
        a[o:o + 8] = NULL_LSA
    a[176:194] = oldhdr[H + 176:H + 194]
    a[200:208] = struct.pack('<q', 0)
    # bkinfo[3] (216..312) left zero: logpb_initialize_backup_info zeroes them (checked by diff vs copydb below)
    a[312:320] = struct.pack('<ii', 0, -1)
    a[344:360] = struct.pack('<QQ', 4, 0)
    p[H:H + 384] = a
    p[12:16] = checksum(p, lps)
    e = bytearray(lps)
    e[0:8] = struct.pack('<q', F)
    e[8:10] = struct.pack('<h', -1)
    e[H:H + 24] = NULL_LSA * 3
    e[H + 24:H + 28] = struct.pack('<i', 1)
    e[H + 28:H + 32] = struct.pack('<i', 35)  # LOG_END_OF_LOG
    e[12:16] = checksum(e, lps)
    with open(new, 'wb') as f:
        f.truncate(npages_total * lps)
        f.seek(0)
        f.write(p)
        f.write(e)
    print(f'wrote {new}: mode={mode} F={F} npages_total={npages_total} logpagesize={lps}')


if __name__ == '__main__':
    c = sys.argv[1]
    if c == 'hdr':
        for k, v in hdr(sys.argv[2]).items():
            print(f'{k}={v}')
    elif c == 'scan':
        scan(sys.argv[2:])
    elif c == 'mklog':
        mklog(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 0)
