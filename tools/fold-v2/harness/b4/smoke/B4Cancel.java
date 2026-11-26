import java.sql.*;

/* B4Cancel <port> <dbA> <dbB>: one client, a session of each database behind one broker, both in SELECT SLEEP(12).
 * After 2 s the statement of dbA is cancelled. Prints each session's token and what became of its statement. */
public class B4Cancel {
    static String tok(Connection c) throws SQLException {
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("SHOW SESSION STATUS")) { rs.next(); return rs.getString(1); }
    }
    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        Connection A = DriverManager.getConnection("jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[1] + ":::", "dba", "");
        Connection B = DriverManager.getConnection("jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[2] + ":::", "dba", "");
        System.out.println("TOKENS " + (tok(A).equals(tok(B)) ? "equal" : "differ"));
        Statement sa = A.createStatement(), sb = B.createStatement();
        String[] res = new String[2];
        long t0 = System.currentTimeMillis();
        Thread ta = new Thread(() -> { try { sa.executeQuery("SELECT SLEEP(12)"); res[0] = "completed"; } catch (SQLException e) { res[0] = "cancelled"; } res[0] += (System.currentTimeMillis() - t0 < 8000 ? " early" : " late"); });
        Thread tb = new Thread(() -> { try { sb.executeQuery("SELECT SLEEP(12)"); res[1] = "completed"; } catch (SQLException e) { res[1] = "cancelled"; } res[1] += (System.currentTimeMillis() - t0 < 8000 ? " early" : " late"); });
        ta.start(); tb.start();
        Thread.sleep(2000);
        try { sa.cancel(); System.out.println("CANCEL sent"); } catch (SQLException e) { System.out.println("CANCEL ERR " + e.getErrorCode() + " " + e.getMessage().replace('\n', ' ')); }
        ta.join(); tb.join();
        System.out.println("A " + res[0]); System.out.println("B " + res[1]);
        A.close(); B.close();
    }
}
