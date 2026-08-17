/*
 * cdclogdump.c — P0 measurement harness for the CUBRID CDC log-extraction API
 * (cubrid_log.h). Connects to a running cub_server with supplemental_log=1,
 * finds the LSA for a start timestamp, then loops cubrid_log_extract() and
 * prints every log item in a human-readable, line-oriented format.
 *
 * Evidence goals (map #30, ticket #33):
 *   - full image vs partial image on UPDATE (changed vs cond columns)
 *   - event position semantics (extract in/out LSA per batch)
 *   - transaction boundaries (COMMIT/ABORT DCL, trigger DML, savepoints)
 *
 * Column values arrive either as in-place native binary (int/int64/float/
 * double/short) or a NUL-terminated string; the server's pack-func code is
 * NOT exposed to the consumer, only a byte length. len==4 is ambiguous
 * (int|float) and len==8 is ambiguous (bigint|double), so every value is
 * dumped as raw hex PLUS all candidate decodings. That ambiguity is itself
 * a P0 finding for the Debezium connector.
 *
 * Build: see Makefile (links against $CUBRID/lib/libcubridcs.so).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <stdint.h>

#include "cubrid_log.h"

static const char *
data_item_type_name (int t)
{
  switch (t)
    {
    case 0: return "DDL";
    case 1: return "DML";
    case 2: return "DCL";
    case 3: return "TIMER";
    case 4: return "ROLLBACK_TO";
    default: return "UNKNOWN";
    }
}

static const char *
dml_type_name (int t)
{
  switch (t)
    {
    case 0: return "INSERT";
    case 1: return "UPDATE";
    case 2: return "DELETE";
    case 3: return "TRIGGER_INSERT";
    case 4: return "TRIGGER_UPDATE";
    case 5: return "TRIGGER_DELETE";
    default: return "UNKNOWN";
    }
}

static const char *
dcl_type_name (int t)
{
  switch (t)
    {
    case 0: return "COMMIT";
    case 1: return "ABORT";
    default: return "UNKNOWN";
    }
}

static const char *
ddl_type_name (int t)
{
  switch (t)
    {
    case 0: return "CREATE";
    case 1: return "ALTER";
    case 2: return "DROP";
    case 3: return "RENAME";
    case 4: return "TRUNCATE";
    default: return "UNKNOWN";
    }
}

static const char *
ddl_object_type_name (int t)
{
  switch (t)
    {
    case 0: return "TABLE";
    case 1: return "INDEX";
    case 2: return "SERIAL";
    case 3: return "VIEW";
    case 4: return "FUNCTION";
    case 5: return "PROCEDURE";
    case 6: return "TRIGGER";
    case 7: return "USER";
    default: return "UNKNOWN";
    }
}

/* LOG_LSA is a 64-bit struct (pageid:48, offset:16 bitfields); the public API
 * flattens it to uint64_t. Print raw + the little-endian bitfield split
 * (low 48 = pageid, high 16 = offset) — labeled a guess until the position
 * decision ticket confirms the layout from this very dump. */
static void
print_lsa (const char *label, uint64_t lsa)
{
  printf ("%s=0x%016llx (pageid?=%llu offset?=%llu)", label,
	  (unsigned long long) lsa,
	  (unsigned long long) (lsa & 0x0000FFFFFFFFFFFFULL),
	  (unsigned long long) (lsa >> 48));
}

static void
print_hex (const char *buf, int len, int max)
{
  int n = len < max ? len : max;
  int i;
  for (i = 0; i < n; i++)
    {
      printf ("%02x", (unsigned char) buf[i]);
    }
  if (len > max)
    {
      printf ("..(+%d)", len - max);
    }
}

static void
print_escaped_string (const char *s, int len, int max)
{
  int n = len < max ? len : max;
  int i;
  putchar ('"');
  for (i = 0; i < n; i++)
    {
      unsigned char c = (unsigned char) s[i];
      if (c == '"' || c == '\\')
	{
	  printf ("\\%c", c);
	}
      else if (isprint (c))
	{
	  putchar (c);
	}
      else
	{
	  printf ("\\x%02x", c);
	}
    }
  if (len > max)
    {
      printf ("..(+%d)", len - max);
    }
  putchar ('"');
}

static void
print_column_value (const char *data, int len)
{
  printf ("len=%d raw=", len);
  if (data == NULL)
    {
      printf ("NULL");
      return;
    }
  print_hex (data, len, 64);

  if (len == 4)
    {
      int iv;
      float fv;
      memcpy (&iv, data, 4);
      memcpy (&fv, data, 4);
      printf (" as_int=%d as_float=%g", iv, fv);
    }
  else if (len == 8)
    {
      long long lv;
      double dv;
      memcpy (&lv, data, 8);
      memcpy (&dv, data, 8);
      printf (" as_bigint=%lld as_double=%g", lv, dv);
    }
  else if (len == 2)
    {
      short sv;
      memcpy (&sv, data, 2);
      printf (" as_short=%d", (int) sv);
    }

  /* string pack codes (5/7/8) deliver a NUL-terminated buffer whose strlen
   * equals len — always show the string reading too */
  printf (" as_str=");
  print_escaped_string (data, len, 256);
}

/* orderable lsa key carried by DML items and ROLLBACK_TO markers:
 * (pageid << 16) | offset — see CDC_LSA_TO_KEY in log_manager.c */
static void
print_lsa_key (const char *label, long long key)
{
  printf ("%s=%lld (pageid=%lld offset=%lld)", label, key, key >> 16, key & 0xFFFF);
}

static void
print_dml (const DML * dml)
{
  int i;

  printf (" dml_type=%d(%s) classoid=%llu num_changed=%d num_cond=%d ",
	  dml->dml_type, dml_type_name (dml->dml_type),
	  (unsigned long long) dml->classoid, dml->num_changed_column, dml->num_cond_column);
  print_lsa_key ("rec_lsa", (long long) dml->rec_lsa);
  putchar ('\n');

  for (i = 0; i < dml->num_changed_column; i++)
    {
      printf ("    changed[%d] col_index=%d ", i, dml->changed_column_index ? dml->changed_column_index[i] : -1);
      print_column_value (dml->changed_column_data ? dml->changed_column_data[i] : NULL,
			  dml->changed_column_data_len ? dml->changed_column_data_len[i] : 0);
      putchar ('\n');
    }
  for (i = 0; i < dml->num_cond_column; i++)
    {
      printf ("    cond[%d] col_index=%d ", i, dml->cond_column_index ? dml->cond_column_index[i] : -1);
      print_column_value (dml->cond_column_data ? dml->cond_column_data[i] : NULL,
			  dml->cond_column_data_len ? dml->cond_column_data_len[i] : 0);
      putchar ('\n');
    }
}

static void
print_item (int seq, const CUBRID_LOG_ITEM * item)
{
  printf ("ITEM #%d trid=%d user=%s type=%d(%s)", seq, item->transaction_id,
	  item->user ? item->user : "(null)", item->data_item_type, data_item_type_name (item->data_item_type));

  switch (item->data_item_type)
    {
    case 0:			/* DDL */
      printf (" ddl_type=%d(%s) obj_type=%d(%s) oid=%llu classoid=%llu stmt_len=%d\n    stmt=",
	      item->data_item.ddl.ddl_type, ddl_type_name (item->data_item.ddl.ddl_type),
	      item->data_item.ddl.object_type, ddl_object_type_name (item->data_item.ddl.object_type),
	      (unsigned long long) item->data_item.ddl.oid,
	      (unsigned long long) item->data_item.ddl.classoid, item->data_item.ddl.statement_length);
      if (item->data_item.ddl.statement)
	{
	  print_escaped_string (item->data_item.ddl.statement,
				(int) strlen (item->data_item.ddl.statement), 4096);
	}
      else
	{
	  printf ("NULL");
	}
      putchar ('\n');
      break;

    case 1:			/* DML */
      print_dml (&item->data_item.dml);
      break;

    case 2:			/* DCL */
      {
	char tbuf[64] = "";
	time_t ts = item->data_item.dcl.timestamp;
	struct tm tmv;
	localtime_r (&ts, &tmv);
	strftime (tbuf, sizeof (tbuf), "%Y-%m-%d %H:%M:%S", &tmv);
	printf (" dcl_type=%d(%s) timestamp=%lld(%s)\n", item->data_item.dcl.dcl_type,
		dcl_type_name (item->data_item.dcl.dcl_type), (long long) ts, tbuf);
      }
      break;

    case 3:			/* TIMER */
      printf (" timestamp=%lld\n", (long long) item->data_item.timer.timestamp);
      break;

    case 4:			/* ROLLBACK_TO — partial rollback marker: buffered DML of this
				 * trid with rec_lsa > this key was undone by the server */
      putchar (' ');
      print_lsa_key ("rollback_to_lsa", (long long) item->data_item.rollback_to.lsa);
      putchar ('\n');
      break;

    default:
      putchar ('\n');
      break;
    }
}

static void
usage (const char *prog)
{
  fprintf (stderr,
	   "usage: %s -d dbname [options]\n"
	   "  -d dbname     database name (required)\n"
	   "  -H host       server host (default: localhost)\n"
	   "  -p port       master port cubrid_port_id (default: 1523)\n"
	   "  -u user       login id (default: dba)\n"
	   "  -w password   login password (default: empty)\n"
	   "  -t epoch      start timestamp for find_lsa (default: now-600)\n"
	   "  -a 0|1        cubrid_log_set_all_in_cond (default: not set)\n"
	   "  -m N          max log items per extract (default: API default)\n"
	   "  -i N          exit after N consecutive empty extracts (default: 5)\n"
	   "  -T sec        extraction timeout seconds (default: API default)\n"
	   "  -f            follow mode: never exit on idle (Ctrl-C to stop)\n", prog);
}

int
main (int argc, char **argv)
{
  char *dbname = NULL;
  char *host = (char *) "localhost";
  char *user = (char *) "dba";
  char *password = (char *) "";
  int port = 1523;
  long long start_ts = 0;
  int all_in_cond = -1;
  int max_log_item = -1;
  int idle_limit = 5;
  int extraction_timeout = -1;
  int follow = 0;
  int opt, rc;

  while ((opt = getopt (argc, argv, "d:H:p:u:w:t:a:m:i:T:f")) != -1)
    {
      switch (opt)
	{
	case 'd': dbname = optarg; break;
	case 'H': host = optarg; break;
	case 'p': port = atoi (optarg); break;
	case 'u': user = optarg; break;
	case 'w': password = optarg; break;
	case 't': start_ts = atoll (optarg); break;
	case 'a': all_in_cond = atoi (optarg); break;
	case 'm': max_log_item = atoi (optarg); break;
	case 'i': idle_limit = atoi (optarg); break;
	case 'T': extraction_timeout = atoi (optarg); break;
	case 'f': follow = 1; break;
	default: usage (argv[0]); return 2;
	}
    }
  if (dbname == NULL)
    {
      usage (argv[0]);
      return 2;
    }
  if (start_ts == 0)
    {
      start_ts = (long long) time (NULL) - 600;
    }

  setvbuf (stdout, NULL, _IOLBF, 0);

  printf ("CONFIG db=%s host=%s port=%d user=%s start_ts=%lld all_in_cond=%d max_log_item=%d idle_limit=%d\n",
	  dbname, host, port, user, start_ts, all_in_cond, max_log_item, idle_limit);

  if (all_in_cond >= 0)
    {
      rc = cubrid_log_set_all_in_cond (all_in_cond);
      printf ("SET all_in_cond(%d) rc=%d\n", all_in_cond, rc);
      if (rc != CUBRID_LOG_SUCCESS)
	{
	  return 1;
	}
    }
  if (max_log_item > 0)
    {
      rc = cubrid_log_set_max_log_item (max_log_item);
      printf ("SET max_log_item(%d) rc=%d\n", max_log_item, rc);
      if (rc != CUBRID_LOG_SUCCESS)
	{
	  return 1;
	}
    }
  if (extraction_timeout > 0)
    {
      rc = cubrid_log_set_extraction_timeout (extraction_timeout);
      printf ("SET extraction_timeout(%d) rc=%d\n", extraction_timeout, rc);
      if (rc != CUBRID_LOG_SUCCESS)
	{
	  return 1;
	}
    }

  rc = cubrid_log_connect_server (host, port, dbname, user, password);
  printf ("CONNECT rc=%d\n", rc);
  if (rc != CUBRID_LOG_SUCCESS)
    {
      fprintf (stderr, "connect failed (rc=%d)\n", rc);
      return 1;
    }

  {
    time_t ts = (time_t) start_ts;
    uint64_t lsa = 0;

    rc = cubrid_log_find_lsa (&ts, &lsa);
    printf ("FIND_LSA rc=%d in_ts=%lld out_ts=%lld ", rc, start_ts, (long long) ts);
    print_lsa ("lsa", lsa);
    putchar ('\n');
    if (rc != CUBRID_LOG_SUCCESS && rc != CUBRID_LOG_SUCCESS_WITH_ADJUSTED_LSA)
      {
	fprintf (stderr, "find_lsa failed (rc=%d)\n", rc);
	cubrid_log_finalize ();
	return 1;
      }

    {
      int round = 0, idle = 0, total_items = 0;

      while (follow || idle < idle_limit)
	{
	  CUBRID_LOG_ITEM *list = NULL;
	  int list_size = 0;
	  uint64_t lsa_in = lsa;

	  rc = cubrid_log_extract (&lsa, &list, &list_size);
	  round++;

	  printf ("EXTRACT round=%d rc=%d n=%d ", round, rc, list_size);
	  print_lsa ("in_lsa", lsa_in);
	  printf (" -> ");
	  print_lsa ("out_lsa", lsa);
	  putchar ('\n');

	  if (rc != CUBRID_LOG_SUCCESS && rc != CUBRID_LOG_SUCCESS_WITH_NO_LOGITEM)
	    {
	      fprintf (stderr, "extract failed (rc=%d)\n", rc);
	      break;
	    }

	  if (list_size > 0 && list != NULL)
	    {
	      CUBRID_LOG_ITEM *it;
	      int seq = 0;
	      int had_real_item = 0;	/* TIMER (type 3) is a ~1s heartbeat the
					 * server emits even with no txn activity;
					 * counting it as "not idle" would make -i
					 * idle-round termination never fire. */
	      for (it = list; it != NULL; it = it->next)
		{
		  print_item (total_items + (++seq), it);
		  if (it->data_item_type != 3)
		    {
		      had_real_item = 1;
		    }
		}
	      total_items += seq;
	      if (had_real_item)
		{
		  idle = 0;
		}
	      else
		{
		  idle++;
		}
	    }
	  else
	    {
	      idle++;
	      sleep (1);
	    }

	  if (list != NULL)
	    {
	      cubrid_log_clear_log_item (list);
	    }
	}
      printf ("DONE total_items=%d rounds=%d\n", total_items, round);
    }
  }

  rc = cubrid_log_finalize ();
  printf ("FINALIZE rc=%d\n", rc);
  return 0;
}
