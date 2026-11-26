set pagination off
set breakpoint pending on
break net_write_stream
commands
silent
printf "WRITE con_status=%d keep=%d autocommit_flag=%d\n", as_info->con_status, as_info->cur_keep_con, as_info->cci_default_autocommit
bt 3
continue
end
continue
