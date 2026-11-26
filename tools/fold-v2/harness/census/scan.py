import subprocess, re, csv, sys, collections
R='/home/cubrid/dev/cubrid-worktree/develop'
OUT='/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2/census'
rows=list(csv.DictReader(open('/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2/commit-stage.tsv'),delimiter='\t'))
pats=collections.OrderedDict([
 ('TLS', r'\bthread_local\b|__thread\b|THREAD_LOCAL|pthread_getspecific|pthread_setspecific|pthread_key'),
 ('ATOMIC', r'std::atomic|\batomic<|ATOMIC_(INC|CAS|TAS|LOAD|STORE)|__sync_|__atomic_|ATOMIC_INC|memory_order'),
 ('SYNC', r'pthread_mutex|std::mutex|pthread_cond|condition_variable|pthread_rwlock|lock_guard|unique_lock|scoped_lock|csect_|CSECT_|critical_section|pthread_spin|sem_(wait|post|init)|futex'),
 ('SHM', r'\bshm|uw_shm|MAP_SHARED|mmap\('),
 ('FD', r'\bsocket\(|\baccept4?\(|sendmsg|recvmsg|SCM_RIGHTS|epoll_|\bpoll\(|\bfcntl\(|\bdup2?\(|\bclose\s*\(|socketpair|O_CLOEXEC|SOCK_'),
 ('THREAD', r'pthread_create|std::thread|pthread_join|pthread_detach|worker_pool|daemon|cubthread::|thread_create|get_entry\(|thread_get_thread_entry_info'),
 ('SIGNAL', r'\bsignal\s*\(|sigaction|SIGPIPE|SIGALRM|SIGUSR|kill\s*\('),
 ('VOLATILE', r'\bvolatile\b'),
 ('STATIC', r'^\s*static\b(?!\s+(inline\s+)?[A-Za-z_][\w:<>,\s\*&]*\s+\**\w+\s*\([^;]*$)(?!.*\)\s*;\s*$)'),
 ('GLOBAL', r'^(?!\s)(?!return|typedef|static|#|//|/\*|\*|else|case|default|goto|extern\s+"C")(?:const\s+)?[A-Za-z_][\w:<>,\*\s&]*?\s\**[A-Za-z_]\w*(\s*\[[^\]]*\])*\s*(=[^=].*|\{.*\})?;\s*$'),
 ('EXTERN', r'^extern\s+(?!"C")'),
])
cre={k:re.compile(v) for k,v in pats.items()}
by=collections.defaultdict(list)
for r in rows: by[r['stage']].append(r)
for st,rs in by.items():
  f=open(f'{OUT}/{st}.raw','w')
  for r in rs:
    sha=r['sha']
    d=subprocess.run(['git','-C',R,'show','--format=','-U0','--no-color',sha,'--','src','cubrid','sa','cs','util','broker','cas','CMakeLists.txt',':!unit_tests'],capture_output=True,text=True).stdout
    fn=None
    for ln in d.splitlines():
      if ln.startswith('+++ '): fn=ln[6:]; continue
      if not ln.startswith('+') or ln.startswith('+++'): continue
      body=ln[1:]
      if fn and ('unit_tests' in fn or fn.endswith(('.java','.py','.sh','.txt','.md','.cmake'))): continue
      tags=[k for k,c in cre.items() if c.search(body)]
      if tags and not re.match(r'^\s*(//|\*|/\*)',body):
        f.write(f"{','.join(tags)}\t{sha[:10]}\t{fn}\t{body.strip()[:200]}\n")
  f.close()
