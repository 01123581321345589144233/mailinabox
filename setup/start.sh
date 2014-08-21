#!/bin/bash
# This is the entry point for configuring the system.
#####################################################

source setup/functions.sh # load our functions

# Check system setup.

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo setup/start.sh"
	echo
	exit
fi

# Check that we are running on Ubuntu 14.04 LTS (or 14.04.xx).
if [ "`lsb_release -d | sed 's/.*:\s*//' | sed 's/14\.04\.[0-9]/14.04/' `" != "Ubuntu 14.04 LTS" ]; then
	echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit
fi

# Check that we have enough memory. Skip the check if we appear to be
# running inside of Vagrant, because that's really just for testing.
TOTAL_PHYSICAL_MEM=$(free -m | grep ^Mem: | sed "s/^Mem: *\([0-9]*\).*/\1/")
if [ $TOTAL_PHYSICAL_MEM -lt 768 ]; then
if [ ! -d /vagrant ]; then
	echo "Your Mail-in-a-Box needs more than $TOTAL_PHYSICAL_MEM MB RAM."
	echo "Please provision a machine with at least 768 MB, 1 GB recommended."
	exit
fi
fi

if [ -t 0 ]; then
	# In an interactive shell...
	# Install 'dialog' so we can ask the user questions. The original motivation for
	# this was being able to ask the user for input even if stdin has been redirected,
	# e.g. if we piped a bootstrapping install script to bash to get started.
	apt_install dialog
	message_box "Mail-in-a-Box Installation" \
		"Hello and thanks for deploying a Mail-in-a-Box!
		\n\nI'm going to ask you a few questions.
		\n\nTo change your answers later, just re-run this script."
fi

# Recall the last settings used if we're running this a second time.
if [ -f /etc/mailinabox.conf ]; then
	# Run any system migrations before proceeding. Since this is a second run,
	# we assume we have Python already installed.
	setup/migrate.py --migrate

	# Load the old .conf file to get existing configuration options loaded
	# into variables with a DEFAULT_ prefix.
	cat /etc/mailinabox.conf | sed s/^/DEFAULT_/ > /tmp/mailinabox.prev.conf
	source /tmp/mailinabox.prev.conf
	rm -f /tmp/mailinabox.prev.conf
fi

# The box needs a name.
if [ -z "$PRIMARY_HOSTNAME" ]; then
	if [ -z "$DEFAULT_PRIMARY_HOSTNAME" ]; then
		# This is the first run. Ask the user for his email address so we can
		# provide the best default for the box's hostname.
		input_box "Your Email Address" \
"What email address are you setting this box up to manage?
\n\nThe part after the @-sign must be a domain name or subdomain
that you control. You can add other email addresses to this
box later (including email addresses on other domain names
or subdomains you control).
\n\nWe've guessed an email address. Backspace it and type in what
you really want.
\n\nEmail Address:" \
			me@`get_default_hostname` \
			EMAIL_ADDR

		if [ -z "$EMAIL_ADDR" ]; then
			# user hit ESC/cancel
			exit
		fi
		while ! management/mailconfig.py validate-email "$EMAIL_ADDR"
		do
			input_box "Your Email Address" \
				"That's not a valid email address.\n\nWhat email address are you setting this box up to manage?" \
				$EMAIL_ADDR \
				EMAIL_ADDR
			if [ -z "$EMAIL_ADDR" ]; then
				# user hit ESC/cancel
				exit
			fi
		done

		# Take the part after the @-sign as the user's domain name, and add
		# 'box.' to the beginning to create a default hostname for this machine.
		DEFAULT_PRIMARY_HOSTNAME=box.$(echo $EMAIL_ADDR | sed 's/.*@//')
	fi

	input_box "Hostname" \
"This box needs a name, called a 'hostname'. The name will form a part of the box's web address.
\n\nWe recommend that the name be a subdomain of the domain in your email
address, so we're suggesting $DEFAULT_PRIMARY_HOSTNAME.
\n\nYou can change it, but we recommend you don't.
\n\nHostname:" \
		$DEFAULT_PRIMARY_HOSTNAME \
		PRIMARY_HOSTNAME

	if [ -z "$PRIMARY_HOSTNAME" ]; then
		# user hit ESC/cancel
		exit
	fi
fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "$PUBLIC_IP" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 4)

	# On the first run, if we got an answer from the Internet then don't
	# ask the user.
	if [[ -z "$DEFAULT_PUBLIC_IP" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IP=$GUESSED_IP

	# Otherwise on the first run at least provide a default.
	elif [[ -z "$DEFAULT_PUBLIC_IP" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 4)

	# On later runs, if the previous value matches the guessed value then
	# don't ask the user either.
	elif [ "$DEFAULT_PUBLIC_IP" == "$GUESSED_IP" ]; then
		PUBLIC_IP=$GUESSED_IP
	fi

	if [ -z "$PUBLIC_IP" ]; then
		input_box "Public IP Address" \
			"Enter the public IP address of this machine, as given to you by your ISP.
			\n\nPublic IP address:" \
			$DEFAULT_PUBLIC_IP \
			PUBLIC_IP

		if [ -z "$PUBLIC_IP" ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "$PUBLIC_IPV6" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 6)
	MATCHED=0
	if [[ -z "$DEFAULT_PUBLIC_IPV6" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IPV6=$GUESSED_IP
	elif [[ "$DEFAULT_PUBLIC_IPV6" == "$GUESSED_IP" ]]; then
		# No IPv6 entered and machine seems to have none, or what
		# the user entered matches what the Internet tells us.
		PUBLIC_IPV6=$GUESSED_IP
		MATCHED=1
	elif [[ -z "$DEFAULT_PUBLIC_IPV6" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 6)
	fi

	if [[ -z "$PUBLIC_IPV6" && $MATCHED == 0 ]]; then
		input_box "IPv6 Address (Optional)" \
			"Enter the public IPv6 address of this machine, as given to you by your ISP.
			\n\nLeave blank if the machine does not have an IPv6 address.
			\n\nPublic IPv6 address:"
			$DEFAULT_PUBLIC_IPV6 \
			PUBLIC_IPV6

		if [ ! $PUBLIC_IPV6_EXITCODE ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Get the IP addresses of the local network interface(s) that are connected
# to the Internet. We need these when we want to have services bind only to
# the public network interfaces (not loopback, not tunnel interfaces).
if [ -z "$PRIVATE_IP" ]; then
	PRIVATE_IP=$(get_default_privateip 4)
fi
if [ -z "$PRIVATE_IPV6" ]; then
	PRIVATE_IPV6=$(get_default_privateip 6)
fi
if [[ -z "$PRIVATE_IP" && -z "$PRIVATE_IPV6" ]]; then
	echo
	echo "I could not determine the IP or IPv6 address of the network inteface"
	echo "for connecting to the Internet. Setup must stop."
	echo
	hostname -I
	route
	echo
	exit
fi

# We need a country code to generate a certificate signing request. However
# if a CSR already exists then we won't be generating a new one and there's
# no reason to ask for the country code now. $STORAGE_ROOT has not yet been
# set so we'll check if $DEFAULT_STORAGE_ROOT and $DEFAULT_CSR_COUNTRY are
# set (the values from the current mailinabox.conf) and if the CSR exists
# in the expected location.
if [ ! -z "$DEFAULT_STORAGE_ROOT" ] && [ ! -z "$DEFAULT_CSR_COUNTRY" ] && [ -f $DEFAULT_STORAGE_ROOT/ssl/ssl_cert_sign_req.csr ]; then
	CSR_COUNTRY=$DEFAULT_CSR_COUNTRY
fi

if [ -z "$CSR_COUNTRY" ]; then
	# Get a list of country codes. Separate codes from country names with a ^.
	# The input_menu function modifies shell word expansion to ignore spaces
	# (since country names can have spaces) and use ^ instead.
	country_code_list=$(grep -v "^#" setup/csr_country_codes.tsv | sed "s/\(..\)\t\([^\t]*\).*/\1^\2/")

	input_menu "Country Code" \
		"Choose the country where you live or where your organization is based.
		\n\n(This is used to create an SSL certificate.)
		\n\nCountry Code:" \
		"$country_code_list" \
		CSR_COUNTRY

	if [ -z "$CSR_COUNTRY" ]; then
		# user hit ESC/cancel
		exit
	fi
fi

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address, or fall back to local network configuration.
	PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IPv6 address, or fall back to local network configuration.
	PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi
if [ "$PRIMARY_HOSTNAME" = "auto-easy" ]; then
	# Generate a probably-unique subdomain under our justtesting.email domain.
	PRIMARY_HOSTNAME=`echo $PUBLIC_IP | sha1sum | cut -c1-5`.justtesting.email
fi

# Show the configuration, since the user may have not entered it manually.
echo
echo "Primary Hostname: $PRIMARY_HOSTNAME"
echo "Public IP Address: $PUBLIC_IP"
if [ ! -z "$PUBLIC_IPV6" ]; then
	echo "Public IPv6 Address: $PUBLIC_IPV6"
fi
if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
	echo "Private IP Address: $PRIVATE_IP"
fi
if [ "$PRIVATE_IPV6" != "$PUBLIC_IPV6" ]; then
	echo "Private IPv6 Address: $PRIVATE_IPV6"
fi
echo

# Run some network checks to make sure setup on this machine makes sense.
if [ -z "$SKIP_NETWORK_CHECKS" ]; then
	. setup/network-checks.sh
fi

# Create the user named "user-data" and store all persistent user
# data (mailboxes, etc.) in that user's home directory.
if [ -z "$STORAGE_ROOT" ]; then
	STORAGE_USER=user-data
	if [ ! -d /home/$STORAGE_USER ]; then useradd -m $STORAGE_USER; fi
	STORAGE_ROOT=/home/$STORAGE_USER
	mkdir -p $STORAGE_ROOT
	echo $(setup/migrate.py --current) > $STORAGE_ROOT/mailinabox.version
	chown $STORAGE_USER.$STORAGE_USER $STORAGE_ROOT/mailinabox.version
fi

# Save the global options in /etc/mailinabox.conf so that standalone
# tools know where to look for data.
cat > /etc/mailinabox.conf << EOF;
STORAGE_USER=$STORAGE_USER
STORAGE_ROOT=$STORAGE_ROOT
PRIMARY_HOSTNAME=$PRIMARY_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
PUBLIC_IPV6=$PUBLIC_IPV6
PRIVATE_IP=$PRIVATE_IP
PRIVATE_IPV6=$PRIVATE_IPV6
CSR_COUNTRY=$CSR_COUNTRY
EOF

# Start service configuration.
. setup/system.sh
. setup/ssl.sh
. setup/dns.sh
. setup/mail-postfix.sh
. setup/mail-dovecot.sh
. setup/mail-users.sh
. setup/dkim.sh
. setup/spamassassin.sh
. setup/web.sh
. setup/webmail.sh
. setup/owncloud.sh
. setup/zpush.sh
. setup/management.sh

# Write the DNS and nginx configuration files.
sleep 5 # wait for the daemon to start
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/dns/update
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/web/update

# If there aren't any mail users yet, create one.
if [ -z "`tools/mail.py user`" ]; then
	# The outut of "tools/mail.py user" is a list of mail users. If there
	# aren't any yet, it'll be empty.

	# If we didn't ask for an email address at the start, do so now.
	if [ -z "$EMAIL_ADDR" ]; then
		# In an interactive shell, ask the user for an email address.
		if [ -t 0 ]; then
			input_box "Mail Account" \
				"Let's create your first mail account.
				\n\nWhat email address do you want?" \
				me@`get_default_hostname` \
				EMAIL_ADDR

			if [ -z "$EMAIL_ADDR" ]; then
				# user hit ESC/cancel
				exit
			fi
			while ! management/mailconfig.py validate-email "$EMAIL_ADDR"
			do
				input_box "Mail Account" \
					"That's not a valid email address.
					\n\nWhat email address do you want?" \
					$EMAIL_ADDR \
					EMAIL_ADDR
				if [ -z "$EMAIL_ADDR" ]; then
					# user hit ESC/cancel
					exit
				fi
			done

		# But in a non-interactive shell, just make something up.
		# This is normally for testing.
		else
			# Use me@PRIMARY_HOSTNAME
			EMAIL_ADDR=me@$PRIMARY_HOSTNAME
			EMAIL_PW=1234
			echo
			echo "Creating a new administrative mail account for $EMAIL_ADDR with password $EMAIL_PW."
			echo
		fi
	else
		echo
		echo "Okay. I'm about to set up $EMAIL_ADDR for you. This account will also"
		echo "have access to the box's control panel."
	fi

	# Create the user's mail account. This will ask for a password if none was given above.
	tools/mail.py user add $EMAIL_ADDR $EMAIL_PW

	# Make it an admin.
	hide_output tools/mail.py user make-admin $EMAIL_ADDR

	# Create an alias to which we'll direct all automatically-created administrative aliases.
	tools/mail.py alias add administrator@$PRIMARY_HOSTNAME $EMAIL_ADDR
fi

echo
echo "-----------------------------------------------"
echo
echo Your Mail-in-a-Box is running.
echo
echo Please log in to the control panel for further instructions at:
echo
if management/whats_next.py --check-primary-hostname; then
	# Show the nice URL if it appears to be resolving and has a valid certificate.
	echo https://$PRIMARY_HOSTNAME/admin
	echo
	echo If there are problems with this URL, instead use:
	echo
fi
echo https://$PUBLIC_IP/admin
echo
echo You will be alerted that the website has an invalid certificate. Check that
echo the certificate fingerprint matches:
echo
openssl x509 -in $STORAGE_ROOT/ssl/ssl_certificate.pem -noout -fingerprint \
        | sed "s/SHA1 Fingerprint=//"
echo
echo Then you can confirm the security exception and continue.
echo

