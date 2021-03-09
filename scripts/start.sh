#!/usr/bin/env bash

cat <<EOF > /var/www/html/wp-config.php
<?php
define( 'DB_NAME', "$DB_NAME" );
define( 'DB_USER', "$DB_USER" );
define( 'DB_PASSWORD', "$DB_PASSWORD" );
define( 'DB_HOST', "$DB_HOST" );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

define( 'AUTH_KEY',         '111111111111111111111111111111111111111111' );
define( 'SECURE_AUTH_KEY',  '222222222222222222222222222222222222222222' );
define( 'LOGGED_IN_KEY',    '333333333333333333333333333333333333333333' );
define( 'NONCE_KEY',        '444444444444444444444444444444444444444444' );
define( 'AUTH_SALT',        '555555555555555555555555555555555555555555' );
define( 'SECURE_AUTH_SALT', '666666666666666666666666666666666666666666' );
define( 'LOGGED_IN_SALT',   '777777777777777777777777777777777777777777' );
define( 'NONCE_SALT',       '888888888888888888888888888888888888888888' );


\$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF

chown -R www-data:www-data /var/www/html

source /etc/apache2/envvars

/usr/sbin/apache2 -DFOREGROUND