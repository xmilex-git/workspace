# Containerfile.ha — HA shell-TC node image for the wf143 final gate (D143-3).
# Extends the ctp-parallel runtime image with the pieces the CTP HA shell TCs
# need on each node: sshd (password auth — CTP's run_remote_script/jsch drives
# the slave over it), ssh client, expect (TC expect scripts), rsync.
#
# Build:  podman build -t ctp-ha:local -f Containerfile.ha .
FROM localhost/ctp-parallel:local

RUN dnf -y install openssh-server openssh-clients expect rsync iproute passwd wget dos2unix \
    && dnf clean all && rm -rf /var/cache/dnf

# Host keys + root password login (isolated podman network only, never published).
RUN ssh-keygen -A \
    && echo 'root:haq-wf143' | chpasswd \
    && sed -i -e 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' \
              -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
              /etc/ssh/sshd_config

# CUBRID env for every shell — sshd exec channels (jsch) run bash
# non-interactively, which sources /root/.bashrc; TCs assume cubrid on PATH.
RUN printf '%s\n' \
      'export CUBRID=/root/CUBRID' \
      'export CUBRID_DATABASES=$CUBRID/databases' \
      'export PATH=$CUBRID/bin:$PATH' \
      'export LD_LIBRARY_PATH=$CUBRID/lib:$CUBRID/cci/lib:${LD_LIBRARY_PATH:-}' \
      'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk' \
      'export LC_ALL=en_US' \
      'export CTP_HOME=/root/cubrid-testtools/CTP' \
      'export init_path=$CTP_HOME/shell/init_path' \
      > /root/.cubrid_env.sh \
    && echo '. /root/.cubrid_env.sh' >> /root/.bashrc \
    && echo '. /root/.cubrid_env.sh' >> /root/.bash_profile

ENTRYPOINT ["/usr/sbin/sshd", "-D"]
