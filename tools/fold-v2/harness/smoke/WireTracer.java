import java.io.*;
import java.math.BigDecimal;
import java.sql.*;
import java.util.*;

/* The tracer smoke's driver on the wire: java WireTracer HOST PORT DB
 * Honors the CUBRID_M0_TRACER_* environment of the in-process tracer it replaces and prints the same lines to
 * CUBRID_M0_TRACER_OUT, so the smoke's cases and expectations stay as they were:
 *   SQL, OUT, PRE, BIND, ISOLATION=RR, SESSIONS, END=1, USER, START_DELAY, REEXEC_DELAY, and <name>_S<n> per session.
 * A session that is not ended (END unset) leaves its connection open; the process exits without closing it. */
public class WireTracer {
    static PrintWriter out;
    static String host, port, db;

    static synchronized void log(String s) { out.println(s); out.flush(); }

    static String env(String name, int sid) {
        String v = System.getenv(name + "_S" + sid);
        return v != null ? v : System.getenv(name);
    }

    static String msg(SQLException e) { return e.getMessage() == null ? "" : e.getMessage().trim().replace('\n', ' '); }

    /* a value as db_fprint_value prints it: strings quoted, numbers bare */
    static String show(Object o) {
        if (o == null) return "NULL";
        if (o instanceof Number) return (o instanceof BigDecimal) ? ((BigDecimal) o).toPlainString() : o.toString();
        return "'" + o.toString().replace("'", "''") + "'";
    }

    static void sleep(String seconds) throws InterruptedException { Thread.sleep(1000L * Integer.parseInt(seconds.trim())); }

    static boolean session(int sid, String sql0) throws Exception {
        String delay = env("CUBRID_M0_TRACER_START_DELAY", sid);
        if (delay != null) sleep(delay);
        String user = env("CUBRID_M0_TRACER_USER", sid);
        Connection c;
        try {
            c = DriverManager.getConnection("jdbc:cubrid:" + host + ":" + port + ":" + db + ":::?connectTimeout=90",
                                            user != null ? user : "DBA", "");
        } catch (SQLException e) {
            log("M0_TRACER: S" + sid + " FAIL db_restart_ex err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
            return false;
        }
        c.setAutoCommit(false);
        log("M0_TRACER: S" + sid + " wire client connected");

        String iso = env("CUBRID_M0_TRACER_ISOLATION", sid);
        if (iso != null) {
            try {
                if (!iso.equals("RR")) throw new SQLException("unknown isolation");
                c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
            } catch (SQLException e) {
                log("M0_TRACER: S" + sid + " FAIL isolation [" + iso + "] msg=[" + msg(e) + "]");
                return false;
            }
            log("M0_TRACER: S" + sid + " isolation set to REPEATABLE READ");
        }

        String pre = env("CUBRID_M0_TRACER_PRE", sid);
        if (pre != null) {
            int n = 0;
            for (String one : pre.split(";")) {
                if (one.trim().isEmpty()) continue;
                n++;
                try (Statement s = c.createStatement()) {
                    s.execute(one.trim());
                    log("M0_TRACER: S" + sid + " pre statement " + n + " executed");
                } catch (SQLException e) {
                    log("M0_TRACER: S" + sid + " FAIL pre statement err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
                    return false;
                }
            }
        }

        String sql = env("CUBRID_M0_TRACER_SQL", sid);
        if (sql == null) sql = sql0;
        PreparedStatement ps;
        try {
            ps = c.prepareStatement(sql);
        } catch (SQLException e) {
            log("M0_TRACER: S" + sid + " FAIL db_compile_statement err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
            return false;
        }
        log("M0_TRACER: S" + sid + " compiled through the wire");

        String bind = System.getenv("CUBRID_M0_TRACER_BIND");
        if (bind != null) {
            int n = 0;
            for (String v : bind.split(",")) ps.setInt(++n, Integer.parseInt(v.trim()));
            log("M0_TRACER: S" + sid + " bound " + n + " host variable(s)");
        }

        String reexec = env("CUBRID_M0_TRACER_REEXEC_DELAY", sid);
        ResultSet rs;
        try {
            if (!ps.execute()) { log("M0_TRACER: S" + sid + " FAIL no result to fetch"); return false; }
            rs = ps.getResultSet();
        } catch (SQLException e) {
            log("M0_TRACER: S" + sid + " FAIL db_execute_statement err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
            return false;
        }
        log("M0_TRACER: S" + sid + " executed");
        try {
            if (!rs.next()) { log("M0_TRACER: S" + sid + " FAIL db_query_first_tuple err=0 msg=[no row]"); return false; }
            log("M0_TRACER: first value = " + show(rs.getObject(1)));
            rs.close();
        } catch (SQLException e) {
            log("M0_TRACER: S" + sid + " FAIL db_query_first_tuple err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
            return false;
        }
        try {
            c.commit();
        } catch (SQLException e) {
            log("M0_TRACER: S" + sid + " FAIL db_commit_transaction err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
            return false;
        }

        /* the kept statement runs again in a new transaction; when that fails it is compiled once more */
        if (reexec != null) {
            sleep(reexec);
            try {
                ResultSet again = ps.executeQuery();
                if (again.next()) log("M0_TRACER: S" + sid + " kept re-execute value = " + show(again.getObject(1)));
                else log("M0_TRACER: S" + sid + " kept re-execute succeeded");
                again.close();
            } catch (SQLException e) {
                log("M0_TRACER: S" + sid + " kept re-execute err=" + e.getErrorCode());
                try {
                    c.prepareStatement(sql).close();
                    log("M0_TRACER: S" + sid + " recompile succeeded err=0");
                } catch (SQLException e2) {
                    log("M0_TRACER: S" + sid + " recompile failed err=" + e2.getErrorCode());
                }
            }
            try { c.commit(); } catch (SQLException e) { /* as the tracer: the outcome is already logged */ }
        }

        if ("1".equals(System.getenv("CUBRID_M0_TRACER_END"))) {
            try {
                ps.close();
                c.close();
            } catch (SQLException e) {
                log("M0_TRACER: S" + sid + " FAIL db_end_session err=" + e.getErrorCode() + " msg=[" + msg(e) + "]");
                return false;
            }
            log("M0_TRACER: S" + sid + " session ended");
        }
        return true;
    }

    public static void main(String[] a) throws Exception {
        host = a[0]; port = a[1]; db = a[2];
        String sql = System.getenv("CUBRID_M0_TRACER_SQL");
        String file = System.getenv("CUBRID_M0_TRACER_OUT");
        out = new PrintWriter(new FileWriter(file != null ? file : "m0_tracer.out"));
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        String sessions = System.getenv("CUBRID_M0_TRACER_SESSIONS");
        int n = sessions != null ? Integer.parseInt(sessions) : 1;
        final boolean[] ok = new boolean[n];
        Thread[] t = new Thread[n];
        for (int i = 0; i < n; i++) {
            final int sid = i + 1;
            t[i] = new Thread(() -> {
                try {
                    ok[sid - 1] = session(sid, sql);
                } catch (Throwable e) {
                    log("M0_TRACER: S" + sid + " FAIL exception " + e);
                }
            });
            t[i].start();
        }
        boolean all = true;
        for (int i = 0; i < n; i++) { t[i].join(); all &= ok[i]; }
        log(all ? "M0_TRACER: SUCCESS" : "M0_TRACER: FAIL");
        String linger = System.getenv("CUBRID_M0_TRACER_LINGER");   /* a probe: the connections stay open */
        if (linger != null) sleep(linger);
        Runtime.getRuntime().halt(all ? 0 : 1);
    }
}
