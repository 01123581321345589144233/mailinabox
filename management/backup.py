#!/usr/bin/python3

# This script performs a backup of all user data:
# 1) System services are stopped while a copy of user data is made.
# 2) An incremental backup is made using rdiff-backup into the
#    directory STORAGE_ROOT/backup/rdiff-history. This directory
#    will contain the latest files plus a complete history for
#    all prior backups.
# 3) The stopped services are restarted.
# 4) The backup directory is compressed into a single file using tar.
# 5) That file is encrypted with a long password stored in backup/secret_key.txt.

import sys, os, os.path, shutil

from utils import exclusive_process, load_environment, shell

# settings
full_backup = "--full" in sys.argv
keep_backups_for = "31D" # destroy backups older than 31 days

env = load_environment()

exclusive_process("backup")

# Ensure the backup directory exists.
backup_dir = os.path.join(env["STORAGE_ROOT"], 'backup')
backup_duplicity_dir = os.path.join(backup_dir, 'duplicity')
os.makedirs(backup_dir, exist_ok=True)

# Stop services.
shell('check_call', ["/usr/sbin/service", "dovecot", "stop"])
shell('check_call', ["/usr/sbin/service", "postfix", "stop"])

# Update the backup mirror directory which mirrors the current
# STORAGE_ROOT (but excluding the backups themselves!).
try:
	shell('check_call', [
		"/usr/bin/duplicity",
		"full" if full_backup else "incr",
		"--no-encryption",
		"--archive-dir", "/tmp/duplicity-archive-dir",
		"--name", "mailinabox",
		"--exclude", backup_dir,
		"--verbosity", "warning",
		env["STORAGE_ROOT"],
		"file://" + backup_duplicity_dir
		])
finally:
	# Start services again.
	shell('check_call', ["/usr/sbin/service", "dovecot", "start"])
	shell('check_call', ["/usr/sbin/service", "postfix", "start"])

# Remove old backups. This deletes all backup data no longer needed
# from more than 31 days ago. Must do this before destroying the
# cache directory or else this command will re-create it.
shell('check_call', [
	"/usr/bin/duplicity",
	"remove-older-than",
	keep_backups_for,
	"--archive-dir", "/tmp/duplicity-archive-dir",
	"--name", "mailinabox",
	"--force",
	"--verbosity", "warning",
	"file://" + backup_duplicity_dir
	])

# Remove old increments. This deletes incremental data obsoleted by
# any subsequent full backups.
shell('check_call', [
	"/usr/bin/duplicity",
	"remove-all-inc-of-but-n-full",
	"1",
	"--archive-dir", "/tmp/duplicity-archive-dir",
	"--name", "mailinabox",
	"--force",
	"--verbosity", "warning",
	"file://" + backup_duplicity_dir
	])

# Remove duplicity's cache directory because it's redundant with our backup directory.
shutil.rmtree("/tmp/duplicity-archive-dir")

# Encrypt all of the new files.
backup_encrypted_dir = os.path.join(backup_dir, 'encrypted')
os.makedirs(backup_encrypted_dir, exist_ok=True)
for fn in os.listdir(backup_duplicity_dir):
	fn2 = os.path.join(backup_encrypted_dir, fn) + ".enc"
	if os.path.exists(fn2): continue

	# Encrypt the backup using the backup private key.
	shell('check_call', [
		"/usr/bin/openssl",
		"enc",
		"-aes-256-cbc",
		"-a",
		"-salt",
		"-in", os.path.join(backup_duplicity_dir, fn),
		"-out", fn2,
		"-pass", "file:%s" % os.path.join(backup_dir, "secret_key.txt"),
		])

	# The backup can be decrypted with:
	# openssl enc -d -aes-256-cbc -a -in latest.tgz.enc -out /dev/stdout -pass file:secret_key.txt | tar -z

# Remove encrypted backups that are no longer needed.
for fn in os.listdir(backup_encrypted_dir):
	fn2 = os.path.join(backup_duplicity_dir, fn.replace(".enc", ""))
	if os.path.exists(fn2): continue
	os.unlink(os.path.join(backup_encrypted_dir, fn))
