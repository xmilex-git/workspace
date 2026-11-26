import java.sql.*;
import java.util.*;

/* B3Trace <db> <scenario> — the scenarios of the B3 trace runs (brokers: RW 36701, RO 36702, SO 36703; the AUTO pair
 * RO 36704 / RW 36705 for "resume"). Prints what every step returned; the trace is the server's TLATRACE file. */
public class B3Trace {
    static String db;
    static Connection conn(int port, String alt) throws SQLException {
        String url = "jdbc:cubrid:127.0.0.1:" + port + ":" + db + ":::?connectTimeout=30" + (alt == null ? "" : "&altHosts=" + alt);
        Connection c = DriverManager.getConnection(url, "dba", "");
        c.setAutoCommit(false);
        return c;
    }
    static Connection tryConn(String name, int port) {
        try { Connection c = conn(port, null); say(name + " connected"); return c; }
        catch (SQLException e) { say(name + " CONNECT ERR " + e.getErrorCode() + " " + msg(e)); return null; }
    }
    static String msg(SQLException e) { return e.getMessage().replace('\n', ' ').replaceAll(",\\[SESSION.*", "").replaceAll("\\[CAS INFO[^\\]]*\\]", "").trim(); }
    static void say(String s) { System.out.println(s); System.out.flush(); }
    static void x(String name, Connection c, String sql) {
        try {
            if (sql.equals("COMMIT")) { c.commit(); say(name + " COMMIT OK"); }
            else if (sql.equals("ROLLBACK")) { c.rollback(); say(name + " ROLLBACK OK"); }
            else if (sql.equals("SAVEPOINT")) { c.setSavepoint("sp" + System.nanoTime()); say(name + " SAVEPOINT OK"); }
            else if (sql.startsWith("CALL ")) { try (CallableStatement cs = c.prepareCall(sql)) { cs.execute(); say(name + " " + sql + " OK"); } }
            else try (Statement st = c.createStatement()) {
                if (st.execute(sql)) { try (ResultSet rs = st.getResultSet()) { say(name + " " + sql + " OK " + (rs.next() ? rs.getString(1) : "(no row)")); } }
                else say(name + " " + sql + " OK " + st.getUpdateCount());
            }
        } catch (SQLException e) { say(name + " " + sql + " ERR " + e.getErrorCode() + " " + msg(e)); }
    }
    static void close(String name, Connection c) { try { c.close(); say(name + " closed"); } catch (SQLException e) { say(name + " CLOSE ERR " + e.getErrorCode()); } }
    static void sh(String... cmd) throws Exception {
        ProcessBuilder pb = new ProcessBuilder(cmd); pb.redirectErrorStream(true); pb.redirectInput(new java.io.File("/dev/null"));
        pb.environment().put("CUBRID_TLA_B3_HB", "1");
        Process p = pb.start(); StringBuilder sb = new StringBuilder(); try (Scanner sc = new Scanner(p.getInputStream())) { while (sc.hasNextLine()) sb.append(sc.nextLine()).append(' '); } String o = sb.toString().trim();
        say("$ " + String.join(" ", cmd) + " -> rc=" + p.waitFor() + " " + o);
        Thread.sleep(500);
    }
    static void mode(String m) throws Exception { sh("cubrid", "changemode", "-m", m, db); }
    static final int RW = 36701, RO = 36702, SO = 36703, ARO = 36704, ARW = 36705;

    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        db = a[0];
        switch (a[1]) {
        case "gates": {
            Connection rw = conn(RW, null);
            x("rw", rw, "INSERT INTO b3t VALUES (1)"); x("rw", rw, "SAVEPOINT"); x("rw", rw, "SELECT b3s.NEXT_VALUE");
            x("rw", rw, "CREATE TABLE b3d (x INT)"); x("rw", rw, "DROP TABLE b3d");
            x("rw", rw, "SELECT check_authorization ('b3t', 1) ON CLASS _db_authorization FROM db_root");   // a method call in a query
            x("rw", rw, "CALL add_user ('B3U', '') ON CLASS db_root"); x("rw", rw, "CALL drop_user ('B3U') ON CLASS db_root");
            x("rw", rw, "COMMIT");
            Connection ro = conn(RO, null);
            x("ro", ro, "SELECT COUNT(*) FROM b3t"); x("ro", ro, "INSERT INTO b3t VALUES (2)"); x("ro", ro, "CREATE TABLE b3d (x INT)");
            x("ro", ro, "SELECT b3s.NEXT_VALUE"); x("ro", ro, "COMMIT"); close("ro", ro);
            tryConn("so", SO);
            x("rw", rw, "INSERT INTO b3t VALUES (3)"); x("rw", rw, "ROLLBACK"); close("rw", rw);
            break; }
        case "readonly": {
            Connection rw = conn(RW, null);
            x("rw", rw, "INSERT INTO b3t VALUES (51)"); x("rw", rw, "ROLLBACK");
            Connection o = conn(RW, null); x("other", o, "SELECT 1"); x("other", o, "COMMIT"); close("other", o);
            x("rw", rw, "INSERT INTO b3t VALUES (52)"); x("rw", rw, "ROLLBACK");
            x("rw", rw, "SAVEPOINT"); x("rw", rw, "ROLLBACK");
            x("rw", rw, "SELECT b3s.NEXT_VALUE"); x("rw", rw, "ROLLBACK");
            x("rw", rw, "SELECT COUNT(*) FROM b3t"); x("rw", rw, "COMMIT"); close("rw", rw);
            break; }
        case "demote": {
            Connection s1 = conn(RW, null);
            x("s1", s1, "INSERT INTO b3t VALUES (11)"); x("s1", s1, "COMMIT");
            mode("standby");                                      // active -> to-be-standby: s1 is registered
            tryConn("s2", RW);                                    // refused: to-be-standby
            x("s1", s1, "INSERT INTO b3t VALUES (12)"); x("s1", s1, "COMMIT");    // the commit closes the connection
            Thread.sleep(1500);                                   // its unregistration takes the server to standby
            x("s1", s1, "SELECT COUNT(*) FROM b3t");              // the driver connects again: refused on a standby
            Connection ro = conn(RO, null);
            x("ro", ro, "SELECT COUNT(*) FROM b3t"); x("ro", ro, "INSERT INTO b3t VALUES (13)");
            x("ro", ro, "SELECT b3s.NEXT_VALUE");                 // the server refuses: reset_on_commit
            x("ro", ro, "COMMIT");
            Thread.sleep(1000);
            Connection so = conn(SO, null);
            x("so", so, "SELECT COUNT(*) FROM b3t"); x("so", so, "INSERT INTO b3t VALUES (14)"); x("so", so, "COMMIT");
            tryConn("s3", RW);                                    // refused: standby
            mode("active");
            x("so", so, "SELECT COUNT(*) FROM b3t"); x("so", so, "COMMIT");      // closes: slave-only on an active
            Thread.sleep(1000);
            Connection rw = conn(RW, null);
            x("rw", rw, "INSERT INTO b3t VALUES (15)"); x("rw", rw, "COMMIT"); x("rw", rw, "SELECT COUNT(*) FROM b3t"); x("rw", rw, "COMMIT");
            close("rw", rw);
            break; }
        case "maint": {
            mode("standby");                                      // no client: straight to standby
            mode("maintenance");
            tryConn("ro", RO);                                    // refused: maintenance
            mode("standby");                                      // maintenance -> to-be-standby -> standby
            Connection ro = conn(RO, null);
            x("ro", ro, "SELECT COUNT(*) FROM b3t"); x("ro", ro, "COMMIT"); close("ro", ro);
            mode("active");
            Connection rw = conn(RW, null); x("rw", rw, "INSERT INTO b3t VALUES (21)"); x("rw", rw, "COMMIT"); close("rw", rw);
            break; }
        case "regrace": {                                         // the server runs with CUBRID_TLA_B3_ADMIT_DELAY_MS=4000
            Connection s1 = conn(RW, null);                       // waits 4 s in its own admission window first
            x("s1", s1, "INSERT INTO b3t VALUES (31)"); x("s1", s1, "COMMIT");
            Thread t = new Thread(() -> tryConn("late", RW));     // admitted on an active server, then waits
            t.start(); Thread.sleep(1500);
            mode("standby");                                      // to-be-standby before "late" registers
            t.join();
            x("s1", s1, "SELECT COUNT(*) FROM b3t"); x("s1", s1, "COMMIT"); close("s1", s1);
            Thread.sleep(1000);
            mode("active");
            break; }
        case "resume": {                                          // AUTO brokers with one slot each
            Connection a1 = conn(ARO, "127.0.0.1:" + ARW);
            x("a", a1, "SELECT COUNT(*) FROM b3t"); x("a", a1, "INSERT INTO b3t VALUES (41)"); x("a", a1, "COMMIT");
            Connection b = conn(ARO, null);                       // takes the RO broker's slot: a yields
            x("b", b, "SELECT 1"); x("b", b, "COMMIT"); close("b", b);
            sh("cubrid", "broker", "off", "b3aro");               // a's next connection goes to its altHost
            Thread.sleep(1000);
            x("a", a1, "INSERT INTO b3t VALUES (42)"); x("a", a1, "COMMIT");      // resumed through the RW broker: runs
            x("a", a1, "SELECT COUNT(*) FROM b3t"); x("a", a1, "COMMIT");
            close("a", a1);
            break; }
        default: throw new RuntimeException("scenario?");
        }
    }
}
