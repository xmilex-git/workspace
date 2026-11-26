import java.sql.*;

/* B3Jdbc <port> <db> <user> <pass> <step>...
 * One connection, autocommit off. Each step is a SQL statement, or COMMIT, ROLLBACK, SAVEPOINT, SLEEP <sec>.
 * Prints one line per step: "<i> OK <update count or first column of the first row>" or "<i> ERR <code> <message>".
 * A connect failure prints "CONNECT ERR <code> <message>". Exit code 0 either way (the script judges). */
public class B3Jdbc {
    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        String url = "jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[1] + ":::?connectTimeout=30";
        Connection c;
        try {
            c = DriverManager.getConnection(url, a[2], a[3]);
        } catch (SQLException e) {
            System.out.println("CONNECT ERR " + e.getErrorCode() + " " + e.getMessage().replace('\n', ' '));
            return;
        }
        c.setAutoCommit(false);
        for (int i = 4; i < a.length; i++) {
            String s = a[i];
            String tag = (i - 3) + " ";
            try {
                if (s.equals("COMMIT")) { c.commit(); System.out.println(tag + "OK commit"); }
                else if (s.equals("ROLLBACK")) { c.rollback(); System.out.println(tag + "OK rollback"); }
                else if (s.equals("SAVEPOINT")) { c.setSavepoint("sp" + i); System.out.println(tag + "OK savepoint"); }
                else if (s.startsWith("SLEEP ")) { Thread.sleep(1000L * Integer.parseInt(s.substring(6))); System.out.println(tag + "OK sleep"); }
                else try (Statement st = c.createStatement()) {
                    if (st.execute(s)) {
                        try (ResultSet rs = st.getResultSet()) { System.out.println(tag + "OK " + (rs.next() ? rs.getString(1) : "(no row)")); }
                    } else System.out.println(tag + "OK " + st.getUpdateCount());
                }
            } catch (SQLException e) {
                System.out.println(tag + "ERR " + e.getErrorCode() + " " + e.getMessage().replace('\n', ' '));
            }
        }
        try { c.close(); } catch (SQLException e) { System.out.println("CLOSE ERR " + e.getErrorCode()); }
    }
}
