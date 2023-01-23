#!/bin/bash
set -e

export REPO_ROOT=`pwd`
[ ! -d "./scripts" ] && echo "Directory ./scripts DOES NOT exist inside $REPO_ROOT, are you running this from the repo root?" && exit 1

function waitForPort {
  x=$(docker exec -it $1 ss -tulpn | grep $2 | wc -l)
  until [ $x -ne 0 ]
  do
    echo Waiting for $1 to open port $2, this usually takes about 10 seconds ... $x
    sleep 1
    x=$(docker exec -it $1 ss -tulpn | grep $2 | wc -l)
  done
  echo $1 port $2 is open
}

docker run -d --network=testnet -e MARIADB_ROOT_PASSWORD=eilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek --name=maria2.docker mariadb --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb-file-per-table=1 --skip-innodb-read-only-compressed
docker run -d --network=testnet --name=nc2.docker nc2

waitForPort maria2.docker 3306
waitForPort nc2.docker 443

docker exec -e DBHOST=maria2.docker -e USER=marie -e PASS=radioactivity -u www-data nc2.docker sh /init.sh
