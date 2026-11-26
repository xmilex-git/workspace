import java.sql.*;

/* M647Jdbc <port> <db> <user> <pass> login | hold | switch <user2> <pass2>
 * prints "USER=<current user>" or "ERR=<code> <message>"; exit code 0 either way (the script judges). */
public class M647Jdbc {
    static String cur(Connection c) throws SQLException {
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("SELECT CURRENT_USER")) { rs.next(); return rs.getString(1); }
    }
    public static void main(String[] a) throws Exception {
        Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
        String url = "jdbc:cubrid:127.0.0.1:" + a[0] + ":" + a[1] + ":::?connectTimeout=60";
        try (Connection c = DriverManager.getConnection(url, a[2], a[3])) {
            System.out.println("USER=" + cur(c));
            if (a[4].equals("hold")) Thread.sleep(6000);
            if (a[4].equals("switch")) {
                try (CallableStatement cs = c.prepareCall("CALL login(?, ?) ON CLASS db_user")) {
                    cs.setString(1, a[5]); cs.setString(2, a[6]); cs.execute();
                    System.out.println("SWITCH USER=" + cur(c));
                } catch (SQLException e) {
                    System.out.println("SWITCH ERR=" + e.getErrorCode() + " " + e.getMessage().replace('\n', ' '));
                    System.out.println("AFTER USER=" + cur(c));
                }
            }
        } catch (SQLException e) {
            System.out.println("ERR=" + e.getErrorCode() + " " + e.getMessage().replace('\n', ' '));
        }
    }
}
