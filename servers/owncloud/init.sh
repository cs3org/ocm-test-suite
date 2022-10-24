php console.php maintenance:install --admin-user $USER --admin-pass $PASS --database "mysql" --database-name "owncloud" --database-user "root" --database-pass "eilohtho9oTahsuongeeTh7reedahPo1Ohwi3aek" --database-host "$DBHOST"
# sed -i "3 i\  'allow_local_remote_servers' => true," config/config.php
sed -i "8 i\      1 => 'oc1.docker'," /var/www/html/config/config.php
sed -i "9 i\      2 => 'oc2.docker'," /var/www/html/config/config.php

