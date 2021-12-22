#!/usr/local/bin/bash

while true; do
  mysql -P 3306 -u appian -p##### -e"insert into ds2.test (name) values ('hello');"
  sleep 2;
done;