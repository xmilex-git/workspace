import java.sql.*;

/* B4Jdbc <port> <db> <user> <pass> <step>...
 * One connection, autocommit off. Each step is a SQL statement, or COMMIT, ROLLBACK, SAVEPOINT, SLEEP <sec>,
 * ROWS <query> (every row, columns space-joined), BIG <MiB> (binds a string of that size into b4big).
 * -Dalt=<port> adds an altHosts broker, -Dct=<sec> sets connectTimeout.
 * Prints one line per step: "<i> OK <update count or first column of the first row>" or "<i> ERR <code> <message>".
 * A connect failure prints "CONNECT ERR <code> <message>". Exit code 0 either way (the script judges). */
public class B4Jdbc {
    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        String url = "jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[1] + ":::?connectTimeout=" + System.getProperty("ct", "30")
            + (System.getProperty("alt") != null ? "&altHosts=127.0.0.1:" + System.getProperty("alt") : "");
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
                else if (s.startsWith("ROWS ")) try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(s.substring(5))) {
                    int n = rs.getMetaData().getColumnCount();
                    while (rs.next()) { StringBuilder b = new StringBuilder(tag + "ROW"); for (int k = 1; k <= n; k++) b.append(' ').append(rs.getString(k)); System.out.println(b); }
                    System.out.println(tag + "OK rows");
                }
                else if (s.startsWith("BIG ")) try (PreparedStatement ps = c.prepareStatement("INSERT INTO b4big VALUES (?)")) {
                    char[] big = new char[Integer.parseInt(s.substring(4)) * 1024 * 1024]; java.util.Arrays.fill(big, 'x');
                    ps.setString(1, new String(big)); System.out.println(tag + "OK " + ps.executeUpdate());
                }
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
