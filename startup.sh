#!/bin/sh -ex

while ! pg_isready -h $DB_HOST -U $DB_USER; do
	echo waiting until $DB_HOST is ready...
	sleep 3
done

export PGPASSWORD=$DB_PASS 

PSQL="psql -q -h $DB_HOST -U $DB_USER $DB_NAME"


if ! psql -ltq -h $DB_HOST -U $DB_USER | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
  psql -q -h $DB_HOST -U $DB_USER -c "CREATE DATABASE $DB_NAME"
fi
$PSQL -c "create extension if not exists pg_trgm"

RESTORE_SCHEMA=$TTRSS_DIR/backups/restore-schema.sql.gz

if [ -r $RESTORE_SCHEMA ]; then
	zcat $RESTORE_SCHEMA | $PSQL
elif ! $PSQL -c 'select * from ttrss_version'; then
	$PSQL < $TTRSS_DIR/schema/ttrss_schema_pgsql.sql
fi

if [ ! -s $TTRSS_DIR/config.php ]; then
	SELF_URL_PATH=$(echo $SELF_URL_PATH | sed -e 's/[\/&]/\\&/g')

	sed \
		-e "s/define('DB_HOST'.*/define('DB_HOST', '$DB_HOST');/" \
		-e "s/define('DB_USER'.*/define('DB_USER', '$DB_USER');/" \
		-e "s/define('DB_NAME'.*/define('DB_NAME', '$DB_NAME');/" \
		-e "s/define('DB_PASS'.*/define('DB_PASS', '$DB_PASS');/" \
		-e "s/define('PLUGINS'.*/define('PLUGINS', 'auth_internal, note, nginx_xaccel');/" \
		-e "s/define('SELF_URL_PATH'.*/define('SELF_URL_PATH','$SELF_URL_PATH');/" \
		< $TTRSS_DIR/config.php-dist > $TTRSS_DIR/config.php

	cat >> $TTRSS_DIR/config.php << EOF
		define('NGINX_XACCEL_PREFIX', '/tt-rss');
EOF
	
fi

crond &

exec /usr/sbin/php-fpm7 -D &
sleep 2
exec /bin/parent caddy --conf /etc/Caddyfile --log stdout --agree=$ACME_AGREE

