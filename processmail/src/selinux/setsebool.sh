#! /bin/bash -x

setsebool -P httpd_enable_homedirs true
setsebool -P httpd_unified true
setsebool -P httpd_can_network_connect true
