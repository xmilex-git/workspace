import java.sql.*;

/* B1b smoke scenarios over the real JDBC driver, MAX_NUM_APPL_SERVER=1 and KEEP_CONNECTION=AUTO.
 *   resume    A sets a session variable and idles; B connects (A yields); A reads the variable again on a new
 *             connection (B yields): the kept session; twice
 *   intran    A holds a transaction open: B's connect waits until A commits
 *   expire N  A is yielded and stays away N seconds (> session_state_timeout + the daemon period): a new session
 *   one       one connect + one read + close */
public class B1bJdbc {
    static String url;
    static Connection connect() throws SQLException { return DriverManager.getConnection(url, "dba", ""); }
    static void say(String s) { System.out.println("B1B_JDBC: " + s); }
    static String one(Connection c, String q) throws SQLException {
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(q)) { rs.next(); return rs.getString(1); }
    }
    static void upd(Connection c, String q) throws SQLException { try (Statement st = c.createStatement()) { st.executeUpdate(q); } }

    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        url = "jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[1] + ":::?connectTimeout=90";
        String mode = a[2];
        if (mode.equals("one")) {
            try (Connection c = connect()) { say("one " + one(c, "SELECT COUNT(*) FROM db_root")); }
        } else if (mode.equals("resume")) {
            Connection A = connect();
            upd(A, "SET @b1b = 7");
            String sidA = one(A, "SELECT 1");
            long t0 = System.currentTimeMillis();
            Connection B = connect();
            long waited = System.currentTimeMillis() - t0;
            say("B connected after " + waited + " ms");
            if (waited > 10000) throw new RuntimeException("B waited " + waited + " ms: A did not yield");
            upd(B, "SET @b1b = 9");
            for (int i = 0; i < 2; i++) {
                String va = one(A, "SELECT @b1b");
                if (!"7".equals(va)) throw new RuntimeException("A read " + va + " round " + i);
                String vb = one(B, "SELECT @b1b");
                if (!"9".equals(vb)) throw new RuntimeException("B read " + vb + " round " + i);
            }
            say("A and B kept their session variables across 4 yields");
            A.close(); B.close();
        } else if (mode.equals("intran")) {
            Connection A = connect();
            upd(A, "DROP TABLE IF EXISTS b1b_t"); upd(A, "CREATE TABLE b1b_t (i INT)");
            A.setAutoCommit(false);
            upd(A, "INSERT INTO b1b_t VALUES (1)");
            final long t0 = System.currentTimeMillis();
            final long[] got = new long[1];
            final String[] seen = new String[1];
            Thread tb = new Thread(() -> { try (Connection B = connect()) { got[0] = System.currentTimeMillis() - t0; seen[0] = one(B, "SELECT COUNT(*) FROM b1b_t"); } catch (Exception e) { e.printStackTrace(); } });
            tb.start();
            Thread.sleep(5000);
            if (got[0] != 0) throw new RuntimeException("B got in after " + got[0] + " ms while A was in a transaction");
            A.commit();
            tb.join(20000);
            say("B connected after " + got[0] + " ms, saw " + seen[0] + " row");
            if (got[0] < 4500 || !"1".equals(seen[0])) throw new RuntimeException("intran: " + got[0] + " " + seen[0]);
            A.setAutoCommit(true);
            upd(A, "DROP TABLE b1b_t");
            A.close();
        } else if (mode.equals("expire")) {
            Connection A = connect();
            upd(A, "SET @b1b = 7");
            try (Connection B = connect()) { one(B, "SELECT 1"); }
            Thread.sleep(Integer.parseInt(a[3]) * 1000L);
            String va;
            try { va = one(A, "SELECT @b1b"); } catch (SQLException e) { va = e.getMessage().contains("not defined") ? "(not defined)" : e.getMessage(); }
            say("after the timeout A read " + va);
            if (!"(not defined)".equals(va)) throw new RuntimeException("the expired session's variable: " + va);
            A.close();
        }
        say("SUCCESS " + mode);
    }
}
