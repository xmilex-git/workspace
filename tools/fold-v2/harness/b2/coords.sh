#!/bin/bash
# coords.sh <worktree>: file:line of every step the B2 models map (first match of a fixed string)
cd "$1" || exit 2
B=src/broker/broker_direct.cpp; A=src/connection/adoption.cpp; D=src/connection/driver_session.cpp; C=src/broker/cas_server_support.cpp
ln() { /usr/bin/grep -n -m1 -F "$2" "$1" | cut -d: -f1; }
while IFS='|' read -r f pat; do
  eval "ff=\$$f"; echo "$(basename $ff):$(ln $ff "$pat") $pat"
done <<'EOL'
B|config_snapshot (manager &m
B|config.seq = ++m.config_seq
B|control_broadcast (manager &m
B|(void) channel_get_or_dial (m, entry->d_name
B|msg_op::SESSION_CONFIG, &config
B|control_thread_run (manager *m)
B|peer.uid == geteuid
B|gettimeofday
B|brd_park_client (SOCKET
B|parked_client *ssl_pc
B|park_complete (manager &m
B|park_drop (manager &m
B|brd_dispatch_job (T_MAX_HEAP_NODE
B|channel_get_or_dial (*m, db_name)
B|if (!brd_wait_for_slot (*m))
B|config_snapshot (*m, body.config)
B|adopt::msg_op::HANDOFF, &body
B|if (handoff_result != 0)
B|(void) send_all (job->clt_sock_fd, &zero
A|handle_handoff (manager &m
A|session_config &latest = m.latest_config[ch.broker_name];
A|m.registry.emplace (token, entry)
A|msg_op::HANDOFF_ACK, &ack
A|handle_session_config (manager &m
A|if (config.seq <= binding.config.seq)
A|binding.config = config;
A|binding.config_changed.store (true)
A|registry_take_config (session_config
A|config_changed.exchange (false)
A|config = current_session->config;
A|registry_session_finished (std::uint32_t
A|m->registry.erase (it);
A|registry_begin_session_cleanup (std::uint32_t
A|binding->closing = true;
A|binding->client_fd = -1;
A|registry_publish_stats (const
A|registry_stats_snapshot (session_stat_row
A|rows[count++] = binding.stats;
A|registry_shutdown_session (int
A|binding_pin pin (pair.second.binding);
A|shutdown (pin.client_fd, SHUT_RD);
A|acl_reload (void)
D|publish_stats (session_stat_row &row)
D|is_first_request = false;
D|cas_server_session_log_begin () != 0
D|cas_log_open (broker_name);
D|cas_init_ssl (params.client_fd) < 0
D|cas_server_acl_check (broker_name
D|cas_log_close (true);
D|cas_server_session_slot_end ();
D|registry_session_finished (params.token);
D|      close (params.client_fd);
C|cas_server_session_slot_begin (int
C|cas_server_session_config_take (void)
C|cas_server_session_log_begin (void)
C|flock (fd, LOCK_EX | LOCK_NB)
C|cas_server_session_slot_end (void)
C|close (cas_Log_lease_fd);
C|cas_server_acl_reload (void)
C|load_guard (cas_Acl_load_mutex)
C|ok = cas_acl_parse (table);
C|cas_Acl_table.swap (table);
C|cas_server_acl_check (const char
C|std::unique_lock<std::mutex> guard (cas_Acl_mutex);
EOL
echo "cas_dispatch.c:$(ln src/broker/cas_dispatch.c 'cas_server_session_config_take ();') config take"
echo "broker_admin_pub.c:$(ln src/broker/broker_admin_pub.c 'admin_session_control (int shm_key') admin_session_control"
echo "connection_sr.c:$(ln src/connection/connection_sr.c 'registry_shutdown_session (tran_index)') kill"
echo "server_support.c:$(ln src/connection/server_support.c 'registry_stats_snapshot (rows') show"
echo "cas_log.c:$(ln src/broker/cas_log.c 'SIGEV_THREAD_ID') timer"
/usr/bin/grep -n "case msg_op::SESSION_CONFIG" src/connection/adoption.cpp | head -2
/usr/bin/grep -n "brd_init (const char" src/broker/broker_direct.cpp | head -1
