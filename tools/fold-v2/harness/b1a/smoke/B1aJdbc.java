import java.sql.*;

/* B1a smoke scenarios over the real JDBC driver; one mode per run.
 *   basic     connect, DDL, bound DML, explicit commit, out-of-band cancel of SLEEP, reconnect (the old B1 smoke)
 *   hold N    open a session, read, keep it idle N seconds, read again, close (a survivor across a broker restart)
 *   one       one connect + one read + close; fails when the broker refuses (FREE_SERVER) or the read fails */
public class B1aJdbc {
    static String url, user, pass;
    static Connection connect() throws SQLException { return DriverManager.getConnection(url, user, pass); }
    static void say(String s) { System.out.println("B1A_JDBC: " + s); }
    static int count(Statement st, String q) throws SQLException {
        try (ResultSet rs = st.executeQuery(q)) { rs.next(); return rs.getInt(1); }
    }

    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        url = "jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[1] + ":::?connectTimeout=90";
        user = "dba"; pass = "";
        String mode = a[2];
        if (mode.equals("one")) {
            try (Connection c = connect(); Statement st = c.createStatement()) {
                say("one count=" + count(st, "SELECT COUNT(*) FROM db_root"));
            }
        } else if (mode.equals("hold")) {
            int secs = Integer.parseInt(a[3]);
            try (Connection c = connect(); Statement st = c.createStatement()) {
                say("hold open count=" + count(st, "SELECT COUNT(*) FROM db_root"));
                Thread.sleep(secs * 1000L);
                say("hold again count=" + count(st, "SELECT COUNT(*) FROM db_root"));
            }
        } else {
            Connection con = connect();
            Statement stmt = con.createStatement();
            stmt.executeUpdate("DROP TABLE IF EXISTS b1a_smoke");
            stmt.executeUpdate("CREATE TABLE b1a_smoke (id INT PRIMARY KEY, v VARCHAR(32))");
            PreparedStatement ins = con.prepareStatement("INSERT INTO b1a_smoke VALUES (?, ?)");
            for (int i = 1; i <= 2; i++) {
                ins.setInt(1, i); ins.setString(2, "row" + i);
                if (ins.executeUpdate() != 1) throw new RuntimeException("insert " + i);
            }
            ins.close();
            if (count(stmt, "SELECT COUNT(*) FROM b1a_smoke") != 2) throw new RuntimeException("count");
            con.setAutoCommit(false);
            stmt.executeUpdate("UPDATE b1a_smoke SET v = 'updated' WHERE id = 1");
            con.commit();
            con.setAutoCommit(true);
            final Statement slow = con.createStatement();
            Thread canceller = new Thread(() -> { try { Thread.sleep(1500); slow.cancel(); } catch (Exception e) { e.printStackTrace(); } });
            canceller.start();
            long begin = System.currentTimeMillis();
            boolean cancelled = false;
            try { slow.executeQuery("SELECT SLEEP(30)"); } catch (SQLException e) { cancelled = true; say("cancel raised: " + e.getMessage().trim()); }
            canceller.join();
            long elapsed = System.currentTimeMillis() - begin;
            if (!cancelled || elapsed > 15000) throw new RuntimeException("cancel did not land: " + cancelled + " " + elapsed + "ms");
            if (count(stmt, "SELECT COUNT(*) FROM b1a_smoke") != 2) throw new RuntimeException("post-cancel count");
            stmt.close(); con.close();
            con = connect(); stmt = con.createStatement();
            try (ResultSet rs = stmt.executeQuery("SELECT v FROM b1a_smoke WHERE id = 1")) {
                rs.next(); if (!"updated".equals(rs.getString(1))) throw new RuntimeException("reconnect read");
            }
            stmt.executeUpdate("DROP TABLE b1a_smoke");
            stmt.close(); con.close();
        }
        say("SUCCESS " + mode);
    }
}
