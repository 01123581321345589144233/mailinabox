# Base system configuration.

apt-get -q update
apt-get -q -y upgrade

# Basic packages.

apt-get -q -y install sqlite3

# Turn on basic services:
#
#   ntp: keeps the system time correct
#
#   fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
#
# These services don't need further configuration and are started immediately after installation.

apt-get install -q -y ntp fail2ban

# Turn on the firewall. First allow incoming SSH, then turn on the firewall. Additional open
# ports will be set up in the scripts that set up those services.
ufw allow ssh
#ufw allow http
#ufw allow https
ufw --force enable

# Mount the storage volume.
export STORAGE_ROOT=/home/ubuntu/storage
mkdir -p storage


