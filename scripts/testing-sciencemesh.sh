#!/usr/bin/env bash

REPO_ROOT=$(pwd)
export REPO_ROOT=${REPO_ROOT}
[ ! -d "./scripts" ] && echo "Directory ./scripts DOES NOT exist inside $REPO_ROOT, are you running this from the repo root?" && exit 1
[ ! -d "./nc-sciencemesh" ] && echo "Directory ./nc-sciencemesh DOES NOT exist inside $REPO_ROOT, did you run ./scripts/init-sciencemesh.sh?" && exit 1
[ ! -d "./nc-sciencemesh/vendor" ] && echo "Directory ./nc-sciencemesh/vendor DOES NOT exist inside $REPO_ROOT. Try: rmdir ./nc-sciencemesh ; ./scripts/init-sciencemesh.sh" && exit 1
[ ! -d "./oc-sciencemesh" ] && echo "Directory ./oc-sciencemesh DOES NOT exist inside $REPO_ROOT, did you run ./scripts/init-sciencemesh.sh?" && exit 1
[ ! -d "./oc-sciencemesh/vendor" ] && echo "Directory ./oc-sciencemesh/vendor DOES NOT exist inside $REPO_ROOT. Try: rmdir ./oc-sciencemesh ; ./scripts/init-sciencemesh.sh" && exit 1

function waitForPort {
  x=$(docker exec -it "${1}" ss -tulpn | grep -c "${2}")
  until [ "${x}" -ne 0 ]
  do
    echo Waiting for "${1}" to open port "${2}", this usually takes about 10 seconds ... "${x}"
    sleep 1
    x=$(docker exec -it "${1}" ss -tulpn | grep -c "${2}")
  done
  echo "${1}" port "${2}" is open
}

# create temp dirctory if it doesn't exist.
[ ! -d "${REPO_ROOT}/temp" ] && mkdir --parents "${REPO_ROOT}/temp"

# copy init files.
cp --force ./docker/scripts/init-owncloud-sciencemesh.sh  ./temp/oc.sh
cp --force ./docker/scripts/init-nextcloud-sciencemesh.sh ./temp/nc.sh

# make sure scripts are executable.
chmod +x "${REPO_ROOT}/docker/scripts/reva-run.sh"
chmod +x "${REPO_ROOT}/docker/scripts/reva-kill.sh"
chmod +x "${REPO_ROOT}/docker/scripts/reva-entrypoint.sh"

docker run --detach --name=meshdir.docker   --network=testnet pondersource/dev-stock-ocmstub
docker run --detach --name=firefox          --network=testnet -p 5800:5800  --shm-size 2g jlesage/firefox:latest
docker run --detach --name=firefox-legacy   --network=testnet -p 5900:5800  --shm-size 2g jlesage/firefox:v1.18.0
docker run --detach --name=collabora.docker --network=testnet -p 9980:9980 -t -e "extra_params=--o:ssl.enable=false" collabora/code:latest 
docker run --detach --name=wopi.docker      --network=testnet -p 8880:8880 -t cs3org/wopiserver:latest

#docker run --detach --name=rclone.docker    --network=testnet  rclone/rclone rcd -vv --rc-user=rcloneuser --rc-pass=eilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek --rc-addr=0.0.0.0:5572 --server-side-across-configs=true --log-file=/dev/stdout


sleep 30

# EFSS1
docker run --detach --network=testnet                                         \
  --name="reva${EFSS1}1.docker"                                               \
  -e HOST="reva${EFSS1}1"                                                     \
  -v "${REPO_ROOT}/reva:/reva"                                                \
  -v "${REPO_ROOT}/docker/revad:/etc/revad"                                   \
  -v "${REPO_ROOT}/docker/tls:/etc/revad/tls"                                 \
  -v "${REPO_ROOT}/docker/scripts/reva-run.sh:/usr/bin/reva-run.sh"           \
  -v "${REPO_ROOT}/docker/scripts/reva-kill.sh:/usr/bin/reva-kill.sh"         \
  -v "${REPO_ROOT}/docker/scripts/reva-entrypoint.sh:/entrypoint.sh"          \
  pondersource/dev-stock-revad

docker run --detach --network=testnet                                         \
  --name=maria1.docker                                                        \
  -e MARIADB_ROOT_PASSWORD=eilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek           \
  mariadb                                                                     \
  --transaction-isolation=READ-COMMITTED                                      \
  --binlog-format=ROW                                                         \
  --innodb-file-per-table=1                                                   \
  --skip-innodb-read-only-compressed

docker run --detach --network=testnet                                         \
  --name="${EFSS1}1.docker"                                                   \
  --add-host "host.docker.internal:host-gateway"                              \
  -e HOST="${EFSS1}1"                                                         \
  -e DBHOST="maria1.docker"                                                   \
  -e USER="einstein"                                                          \
  -e PASS="relativity"                                                        \
  -v "${REPO_ROOT}/temp/${EFSS1}.sh:/${EFSS1}-init.sh"                        \
  -v "${REPO_ROOT}/$EFSS1-sciencemesh:/var/www/html/apps/sciencemesh"         \
  -v "${REPO_ROOT}/docker/configs/20-xdebug.ini:/etc/php/7.4/cli/conf.d/20-xdebug.ini" \
  -v "${REPO_ROOT}/docker/configs/20-xdebug.ini:/etc/php/8.2/cli/conf.d/20-xdebug.ini" \
  "pondersource/dev-stock-${EFSS1}1-sciencemesh"

# EFSS2
docker run --detach --network=testnet                                         \
  --name="reva${EFSS2}2.docker"                                               \
  -e HOST="reva${EFSS2}2"                                                     \
  -v "${REPO_ROOT}/reva:/reva"                                                \
  -v "${REPO_ROOT}/docker/revad:/etc/revad"                                   \
  -v "${REPO_ROOT}/docker/tls:/etc/revad/tls"                                 \
  -v "${REPO_ROOT}/docker/scripts/reva-run.sh:/usr/bin/reva-run.sh"           \
  -v "${REPO_ROOT}/docker/scripts/reva-kill.sh:/usr/bin/reva-kill.sh"         \
  -v "${REPO_ROOT}/docker/scripts/reva-entrypoint.sh:/entrypoint.sh"          \
  pondersource/dev-stock-revad

docker run --detach --network=testnet                                         \
  --name=maria2.docker                                                        \
  -e MARIADB_ROOT_PASSWORD=eilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek           \
  mariadb                                                                     \
  --transaction-isolation=READ-COMMITTED                                      \
  --binlog-format=ROW                                                         \
  --innodb-file-per-table=1                                                   \
  --skip-innodb-read-only-compressed

docker run --detach --network=testnet                                         \
  --name="${EFSS2}2.docker"                                                   \
  --add-host "host.docker.internal:host-gateway"                              \
  -e HOST="${EFSS2}2"                                                         \
  -e DBHOST="maria2.docker"                                                   \
  -e USER="marie"                                                             \
  -e PASS="radioactivity"                                                     \
  -v "${REPO_ROOT}/temp/${EFSS2}.sh:/${EFSS2}-init.sh"                        \
  -v "${REPO_ROOT}/$EFSS2-sciencemesh:/var/www/html/apps/sciencemesh"         \
  -v "${REPO_ROOT}/docker/configs/20-xdebug.ini:/etc/php/7.4/cli/conf.d/20-xdebug.ini" \
  -v "${REPO_ROOT}/docker/configs/20-xdebug.ini:/etc/php/8.2/cli/conf.d/20-xdebug.ini" \
  "pondersource/dev-stock-${EFSS2}2-sciencemesh"

# EFSS1
waitForPort maria1.docker 3306
waitForPort "${EFSS1}1.docker" 443

docker exec -u www-data "${EFSS1}1.docker" sh "/${EFSS1}-init.sh"

# run db injections.
docker exec maria1.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'iopUrl', 'https://reva${EFSS1}1.docker/');"

docker exec maria1.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'revaSharedSecret', 'shared-secret-1');"

docker exec maria1.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'meshDirectoryUrl', 'https://meshdir.docker/meshdir');"

docker exec maria1.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'inviteManagerApikey', 'invite-manager-endpoint');"

# EFSS2
waitForPort maria2.docker 3306
waitForPort "${EFSS2}2.docker" 443

docker exec -u www-data "${EFSS2}2.docker" sh "/${EFSS2}-init.sh"

docker exec maria2.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'iopUrl', 'https://reva${EFSS2}2.docker/');"

docker exec maria2.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'revaSharedSecret', 'shared-secret-1');"

docker exec maria2.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'meshDirectoryUrl', 'https://meshdir.docker/meshdir');"

docker exec maria2.docker mariadb -u root -peilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek efss                                                               \
  -e "insert into oc_appconfig (appid, configkey, configvalue) values ('sciencemesh', 'inviteManagerApikey', 'invite-manager-endpoint');"

# instructions.
echo "Now browse to http://ocmhost:5800 and inside there to https://${EFSS1}1.docker"
echo "Log in as einstein / relativity"
echo "Go to the ScienceMesh app and generate a token"
echo "Click it to go to the meshdir server, and choose ${EFSS2}2 there."
echo "Log in on https://${EFSS2}2.docker as marie / radioactivity"
