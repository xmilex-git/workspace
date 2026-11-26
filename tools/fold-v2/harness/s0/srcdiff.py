import re,subprocess,sys
def files(ref,path):
    t=subprocess.run(['git','show',f'{ref}:{path}'],capture_output=True,text=True).stdout
    return set(re.findall(r'\$\{\w+_DIR\}/[\w./-]+\.(?:c|cpp)\b',t)), t
def half(t):
    m=re.search(r'set\(CLIENT_HALF_SOURCES(.*?)\)',t,re.S)
    return set(re.findall(r'\$\{\w+_DIR\}/[\w./-]+\.(?:c|cpp)\b',m.group(1))) if m else set()
for ref,label in (('eb88ab4ea','old-base'),(sys.argv[1],'new')):
    sa,_=files(ref,'sa/CMakeLists.txt')
    sv,svt=files(ref,'cubrid/CMakeLists.txt')
    h=half(svt) if ref!='eb88ab4ea' else half(subprocess.run(['git','show','9292336793:cubrid/CMakeLists.txt'],capture_output=True,text=True).stdout)
    globals()[label.replace('-','_')]=(sa-(sv-h)-h, sa, sv, h)
o=old_base[0]; n=new[0]
print('excluded only in new:',sorted(n-o))
print('excluded only in old:',sorted(o-n))
print('half not in sa:',sorted(new[3]-new[1]))
