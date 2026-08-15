# Builds cdclogdump against the ACTIVE CUBRID install ($CUBRID).
# The install must carry include/cubrid_log.h and lib/libcubridcs.so
# (any recent develop build does).
#
#   CUBRID=$HOME/htap-cdc/CUBRID-11.5-htapcdc make

CUBRID ?= $(error CUBRID env var required — point it at the CUBRID install)

CC      ?= gcc
CFLAGS  += -O0 -g -Wall -I$(CUBRID)/include
LDFLAGS += -L$(CUBRID)/lib -Wl,-rpath,$(CUBRID)/lib
LDLIBS  += -lcubridcs

cdclogdump: cdclogdump.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

clean:
	rm -f cdclogdump

.PHONY: clean
