#! /bin/bash
# Script to find out postfix's uid
# 1) Append .../afmap/etc/aliases to /etc/aliases, and run 'newaliases'
# 2) Ensure that entire path "/home/sandbox/labeller/processmail/src/processmail_test.sh"
#    has permissions "o+rx"
# 3) As user sandbox, send email to processmail_test1@localhost
# 4) Check postfix uid in /tmp/id.test
# 5) Edit Makefile to set MTA_USER to that uid, and rebuild .../bin/processmail
# 6) As root, delete /tmp/id.test
# 7) Remove o+rx permissions from .../processmail/src and 
#    .../processmail/src/processmail_test.sh
# 8) As user sandbox, send email to processmail_test2@localhost
# 9) Check for sandbox uid and umask 0007 in /tmp/id.test
#
# NOTE: if selinux is enabled, you may need to run on each *.pp file:
#       semodule -i postfix_<perm>.pp

id >/tmp/id.test
umask >>/tmp/id.test
env >>/tmp/id.test
