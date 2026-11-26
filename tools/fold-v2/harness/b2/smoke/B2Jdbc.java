import java.sql.*;
import java.util.*;

/* B2 smoke driver: java B2Jdbc HOST PORT DB USER FLAGS command...
 *   FLAGS    "ssl" adds useSSL=true, "-" nothing
 *   q:SQL    query, prints the first column of every row
 *   rows:SQL query, prints every row as a|b|c
 *   u:SQL    update
 *   s:N      sleep N seconds
 *   gk:SQL   insert with RETURN_GENERATED_KEYS (autocommit), prints the keys
 *   batch:SQL|a|b|...  prepared batch, one int bind per item
 *   prep:N   prepares N statements and keeps them open, prints how many the broker's cap allowed
 * A failed command prints "ERR <code> <message>" and the run goes on. */
public class B2Jdbc {
    static void say(String s) { System.out.println("B2: " + s); System.out.flush(); }

    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        String url = "jdbc:cubrid:" + a[0] + ":" + a[1] + ":" + a[2] + ":::?connectTimeout=90" + (a[4].equals("ssl") ? "&useSSL=true" : "");
        Connection c;
        try {
            c = DriverManager.getConnection(url, a[3], "");
        } catch (SQLException e) {
            say("CONNECT ERR " + e.getErrorCode() + " " + e.getMessage().trim().replace('\n', ' '));
            System.exit(3);
            return;
        }
        say("connected");
        List<Statement> kept = new ArrayList<>();
        for (int i = 5; i < a.length; i++) {
            String cmd = a[i];
            int colon = cmd.indexOf(':');
            String op = cmd.substring(0, colon), arg = cmd.substring(colon + 1);
            try {
                if (op.equals("s")) {
                    Thread.sleep((long) (Double.parseDouble(arg) * 1000));
                } else if (op.equals("u")) {
                    try (Statement st = c.createStatement()) { say("u " + st.executeUpdate(arg)); }
                } else if (op.equals("q") || op.equals("rows")) {
                    try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(arg)) {
                        int n = rs.getMetaData().getColumnCount();
                        while (rs.next()) {
                            StringBuilder sb = new StringBuilder();
                            for (int k = 1; k <= (op.equals("q") ? 1 : n); k++) { if (k > 1) sb.append('|'); sb.append(rs.getString(k)); }
                            say(op + " " + sb);
                        }
                    }
                } else if (op.equals("gk")) {
                    try (Statement st = c.createStatement()) {
                        st.executeUpdate(arg, Statement.RETURN_GENERATED_KEYS);
                        try (ResultSet rs = st.getGeneratedKeys()) { while (rs.next()) say("gk " + rs.getString(1)); }
                    }
                } else if (op.equals("batch")) {
                    String[] p = arg.split("\\|");
                    try (PreparedStatement ps = c.prepareStatement(p[0])) {
                        for (int k = 1; k < p.length; k++) { ps.setInt(1, Integer.parseInt(p[k])); ps.addBatch(); }
                        say("batch " + ps.executeBatch().length);
                    }
                } else if (op.equals("prep")) {
                    int ok = 0;
                    for (int k = 0; k < Integer.parseInt(arg); k++) {
                        try { PreparedStatement ps = c.prepareStatement("SELECT " + k + " + ?"); ps.setInt(1, 1); ps.executeQuery(); kept.add(ps); ok++; }
                        catch (SQLException e) { say("prep stop " + e.getErrorCode()); break; }
                    }
                    say("prep " + ok);
                }
            } catch (SQLException e) {
                say("ERR " + e.getErrorCode() + " " + e.getMessage().trim().replace('\n', ' '));
            }
        }
        for (Statement s : kept) { try { s.close(); } catch (SQLException e) { } }
        c.close();
        say("done");
    }
}
