# list functions in network_interface_cl.c whose body has a CS_MODE block but no fold (#else / SERVER_MODE) branch
import re, sys
src = open(sys.argv[1]).read().split('\n')
i = 0; out = []
while i < len(src):
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*) \(', src[i])
    if m and i > 0 and not src[i].endswith(';'):
        name = m.group(1); start = i
        # find body open
        j = i
        while j < len(src) and src[j] != '{': j += 1
        k = j + 1; depth = 1
        while k < len(src) and not src[k].startswith('}'): k += 1
        body = src[j:k]
        has_cs = any(re.match(r'#\s*if.*defined\s*\(?\s*CS_MODE', l) for l in body)
        has_else = any(re.match(r'#\s*(else|elif)', l) for l in body)
        if has_cs and not has_else:
            out.append((start + 1, name))
        i = k
    i += 1
for ln, n in out: print(ln, n)
