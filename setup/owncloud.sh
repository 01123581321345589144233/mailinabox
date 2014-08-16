#!/bin/bash
# Owncloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-imap php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcache unzip

apt-get purge -qq -y owncloud*

# Install ownCloud from source if it is not already present
# TODO: Check version?
if [ ! -d /usr/local/lib/owncloud ]; then
	echo installing ownCloud...
	rm -f /tmp/owncloud.zip
	wget -qO /tmp/owncloud.zip https://download.owncloud.org/community/owncloud-7.0.1.zip
	unzip -q /tmp/owncloud.zip -d /usr/local/lib
	rm -f /tmp/owncloud.zip
fi

# Create a configuration file.
TIMEZONE=`cat /etc/timezone`
instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
cat - > /usr/local/lib/owncloud/config/config.php <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '$STORAGE_ROOT/owncloud',

  'instanceid' => '$instanceid',

  'trusted_domains' => 
    array (
      0 => '$PRIMARY_HOSTNAME',
    ),
  'forcessl' => true, # if unset/false, ownCloud sends a HSTS=0 header, which conflicts with nginx config

  'overwritewebroot' => '/cloud',
  'user_backends' => array(
    array(
      'class'=>'OC_User_IMAP',
      'arguments'=>array('{localhost:993/imap/ssl/novalidate-cert}')
    )
  ),
  "memcached_servers" => array (
    array('localhost', 11211),
  ),
  'mail_smtpmode' => 'sendmail',
  'mail_smtpsecure' => '',
  'mail_smtpauthtype' => 'LOGIN',
  'mail_smtpauth' => false,
  'mail_smtphost' => '',
  'mail_smtpport' => '',
  'mail_smtpname' => '',
  'mail_smtppassword' => '',
  'mail_from_address' => 'owncloud',
  'mail_domain' => '$PRIMARY_HOSTNAME',
  'logtimezone' => '$TIMEZONE',
);
?>
EOF

# Create an auto-configuration file to fill in database settings.
adminpassword=$(dd if=/dev/random bs=40 count=1 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
cat - > /usr/local/lib/owncloud/config/autoconfig.php <<EOF;
<?php
\$AUTOCONFIG = array (
  # storage/database
  'directory' => '$STORAGE_ROOT/owncloud',
  'dbtype' => 'sqlite3',

  # create an administrator account with a random password so that
  # the user does not have to enter anything on first load of ownCloud
  'adminlogin'    => 'root',
  'adminpass'     => '$adminpassword',
);
?>
EOF

# Set permissions
mkdir -p $STORAGE_ROOT/owncloud
chown -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

# Execute ownCloud's setup step, which creates the ownCloud sqlite database.
# It also wipes it if it exists. And it deletes the autoconfig.php file.
(cd /usr/local/lib/owncloud; sudo -u www-data php /usr/local/lib/owncloud/index.php;)

# Enable/disable apps. Note that this must be done after the ownCloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows ownCloud to use IMAP for login.
hide_output php /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output php /usr/local/lib/owncloud/console.php app:enable user_external

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php5/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Use Crontab instead of AJAX/webcron in ownCloud
# TODO: somehow change the cron option in ownClouds config, not exposed afaik?
(crontab -u www-data -l; echo "*/15  *  *  *  * php -f /usr/local/lib/owncloud/cron.php" ) | crontab -u www-data -

# Finished.
php5enmod imap
restart_service php5-fpm
