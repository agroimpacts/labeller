#
# Author: Dennis McRitchie
# Based on Makefile by: Bas van der Vlies & Michel Jouvin
#
OWNER=$(shell stat -c %U processmail)
DESTDIR=/home/$(OWNER)/afmap/processmail/bin

MTA_USER=nobody
HAVE_INITGROUPS=1
DEBUG=1

CC=gcc
CFLAGS=-DMTA_USER=\"$(MTA_USER)\" -DHAVE_INITGROUPS=$(HAVE_INITGROUPS) -DDEBUG=$(DEBUG)

WRAPPER_SRC=processmail.c

all: processmail

processmail: $(WRAPPER_SRC) Makefile
	$(CC) $(CFLAGS) -o $@ processmail.c

install: Makefile
	install -d $(DESTDIR)
	install -m 4111 -o root processmail $(DESTDIR)

clean:
	rm processmail
