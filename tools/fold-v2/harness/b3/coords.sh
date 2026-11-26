#!/bin/bash
# coords.sh <worktree>: file:line of every code site MAP.md names
cd "$1" || exit 2
c() { /usr/bin/grep -n -- "$2" "$1" | head -${3:-1} | sed "s|^|$1:|" | cut -c1-150; }
c src/connection/driver_session.cpp 'synthesize_client_type (int'
c src/connection/driver_session.cpp 'admission_check (int'
c src/connection/driver_session.cpp 'const char \*const deny'
c src/connection/driver_session.cpp 'ERR_CSS_ERROR_FROM_SERVER'
c src/connection/driver_session.cpp 'boot_resume_client (&credential'
c src/connection/driver_session.cpp 'db_restart_ex ("driver_session"'
c src/connection/driver_session.cpp 'boot_unregister_client (tm_Tran_index)'
c src/connection/driver_session.cpp 'conn->client_type = '
c src/connection/driver_session.cpp 'ux_end_tran (CCI_TRAN_ROLLBACK'
c src/connection/adoption.cpp 'synthesize_client_type (body'
c src/connection/adoption.cpp 'css_increment_num_conn ((BOOT'
c src/connection/adoption.cpp 'css_decrement_num_conn' 3
c src/broker/broker_direct.cpp 'body.access_mode'
c src/communication/network_interface_cl.c '^modification_is_refused'
c src/communication/network_interface_cl.c 'reset_on_commit = true'
c src/communication/network_interface_cl.c 'xtran_should_connection_reset' 2
c src/communication/network_interface_cl.c 'const bool has_updated' 2
c src/communication/network_interface_cl.c '^exit_server (const'
c src/communication/network_interface_cl.c '^tran_server_commit'
c src/communication/network_interface_cl.c '^tran_server_abort'
c src/compat/db.h 'define db_Client_disable_modifications' 2
c src/compat/db.h 'define CHECK_MODIFICATION' 3
c src/compat/db_admin.c 'db_Client_disable_modifications' 6
c src/transaction/boot_cl.c 'db_Client_disable_modifications'
c src/transaction/boot_cl.c 'db_disable_modification ()' 2
c src/method/query_method.cpp 'db_disable_modification ()'
c src/transaction/log_tran_table.c 'tdes->disable_modifications = ' 4
c src/transaction/log_tran_table.c '^logtb_disable_update'
c src/transaction/log_tran_table.c '^logtb_enable_update'
c src/transaction/log_tran_table.c '^logtb_clear_tdes'
c src/transaction/log_tran_table.c '^logtb_count_clients'
c src/transaction/transaction_sr.c '^xtran_should_connection_reset'
c src/connection/server_support.c '^css_change_ha_server_state'
c src/connection/server_support.c '^css_check_ha_server_state_for_client'
c src/connection/server_support.c '^css_transit_ha_server_state'
c src/connection/server_support.c 'logtb_disable_update (thread_p)' 3
c src/connection/server_support.c 'logtb_enable_update (thread_p)' 3
c src/transaction/boot_sr.c 'css_check_ha_server_state_for_client' 2
c src/transaction/boot_sr.c 'logtb_disable_update (NULL)'
c src/transaction/boot_sr.c 'css_change_ha_server_state (thread_p'
c src/transaction/log_impl.h 'define CHECK_MODIFICATION_NO_RETURN(thread_p, error)' 2
c src/communication/network_sr.c 'action_attribute & CHECK_DB_MODIFICATION'
c src/query/serial.c 'CHECK_MODIFICATION_NO_RETURN' 2
c src/query/query_executor.c 'CHECK_MODIFICATION_NO_RETURN' 5
c src/object/work_space.c 'db_Client_disable_modifications'
c src/communication/network_interface_sr.cpp 'conn->reset_on_commit = true'
c src/communication/network_interface_sr.cpp '^need_to_abort_tran'
c src/broker/cas_execute.c 'as_info->reset_flag = TRUE'
c src/broker/cas_function.c 'restart_is_needed () || as_info->reset_flag'
/usr/bin/grep -n 'RETURN_IF_MODIFICATION_REFUSED (thread_p' src/communication/network_interface_cl.c | cut -d: -f1 | tr '\n' ' '; echo
