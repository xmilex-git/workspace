// CBRD-27365 smoke — 역방향 커서(cursor_prev_tuple / qfile_scan_prev) 1회 확인.
// CAS scrollable fetch 는 모든 SELECT 에 적용되므로(#184) TYPE_SCROLL_INSENSITIVE 로 끝에서 앞으로 읽는다.
// 빌드/실행 (run_smoke.sh 가 수행):
//   javac ScrollSmoke.java && java -cp .:$CUBRID/jdbc/cubrid_jdbc.jar ScrollSmoke <broker_port> <db>
// 기대 출력: expected_scroll.out
import java.sql.*;

public class ScrollSmoke {
  public static void main(String[] a) throws Exception {
    Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
    String url = "jdbc:cubrid:localhost:" + a[0] + ":" + a[1] + ":dba::";
    try (Connection c = DriverManager.getConnection(url)) {
      Statement st = c.createStatement();
      st.executeUpdate("DROP TABLE IF EXISTS t_scroll");
      st.executeUpdate("CREATE TABLE t_scroll (id INT, v VARCHAR(50), d DOUBLE)");
      for (int i = 1; i <= 30; i++) {
        StringBuilder rep = new StringBuilder(); for (int k = 0; k < i; k++) rep.append('s');
        String v = (i % 5 == 0) ? "NULL" : "'" + rep + "'";
        String d = (i % 7 == 0) ? "NULL" : String.valueOf(i * 0.5);
        st.executeUpdate("INSERT INTO t_scroll VALUES (" + i + "," + v + "," + d + ")");
      }
      c.commit();
      Statement s2 = c.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
      ResultSet rs = s2.executeQuery("SELECT id, v, d FROM t_scroll ORDER BY id");
      rs.afterLast();
      StringBuilder sb = new StringBuilder();
      while (rs.previous()) {
        sb.append(rs.getInt(1)).append('|').append(rs.getString(2)).append('|').append(rs.getString(3)).append('\n');
      }
      System.out.print(sb);
      rs.absolute(3);  System.out.println("abs3=" + rs.getInt(1) + "|" + rs.getString(2));
      rs.relative(-2); System.out.println("rel-2=" + rs.getInt(1) + "|" + rs.getString(2));
      rs.last();       System.out.println("last=" + rs.getInt(1) + "|" + rs.getString(3));
      rs.first();      System.out.println("first=" + rs.getInt(1) + "|" + rs.getString(3));
      rs.close(); s2.close();
      st.executeUpdate("DROP TABLE t_scroll");
      c.commit();
    }
  }
}
