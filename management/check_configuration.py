# Checks that the upstream DNS has been set correctly and that
# SSL certificates have been signed, and if not tells the user
# what to do next.

import os, os.path, re, subprocess

import dns.reversename, dns.resolver

from dns_update import get_dns_zones
from web_update import get_web_domains, get_domain_ssl_files

from utils import shell, sort_domains

def run_checks(env):
	# Get the list of domains we serve DNS zones for (i.e. does not include subdomains).
	dns_zonefiles = dict(get_dns_zones(env))
	dns_domains = set(dns_zonefiles)

	# Get the list of domains we serve HTTPS for.
	web_domains = set(get_web_domains(env))

	# Check the domains.
	for domain in sort_domains(dns_domains | web_domains, env):
		print(domain)
		print("=" * len(domain))
		if domain == env["PUBLIC_HOSTNAME"]: check_primary_hostname_dns(domain, env)
		if domain in dns_domains: check_dns_zone(domain, env, dns_zonefiles)
		check_mx(domain, env)
		check_ssl_cert(domain, env)
		print()

def check_primary_hostname_dns(domain, env):
	# Check that the ns1/ns2 hostnames resolve to A records. This information probably
	# comes from the TLD since the information is set at the registrar.
	ip = query_dns("ns1." + domain, "A") + '/' + query_dns("ns2." + domain, "A")
	if ip == env['PUBLIC_IP'] + '/' + env['PUBLIC_IP']:
		print_ok("Nameserver IPs are correct at registrar. [ns1/ns2.%s => %s]" % (env['PUBLIC_HOSTNAME'], env['PUBLIC_IP']))
	else:
		print_error("""Nameserver IP addresses are incorrect. The ns1.%s and ns2.%s nameservers must be configured at your domain name
			registrar as having the IP address %s. They currently report addresses of %s. It may take several hours for
			public DNS to update after a change."""
			% (env['PUBLIC_HOSTNAME'], env['PUBLIC_HOSTNAME'], env['PUBLIC_IP'], ip))

	# Check that PUBLIC_HOSTNAME resolves to PUBLIC_IP in public DNS.
	ip = query_dns(domain, "A")
	if ip == env['PUBLIC_IP']:
		print_ok("Domain resolves to box's IP address. [%s => %s]" % (env['PUBLIC_HOSTNAME'], env['PUBLIC_IP']))
	else:
		print_error("""This domain must resolve to your box's IP address (%s) in public DNS but it currently resolves
			to %s. It may take several hours for public DNS to update after a change. This problem may result from other
			issues listed here."""
			% (env['PUBLIC_IP'], ip))

	# Check reverse DNS on the PUBLIC_HOSTNAME. Note that it might not be
	# a DNS zone if it is a subdomain of another domain we have a zone for.
	ipaddr_rev = dns.reversename.from_address(env['PUBLIC_IP'])
	existing_rdns = query_dns(ipaddr_rev, "PTR")
	if existing_rdns == domain:
		print_ok("Reverse DNS is set correctly at ISP. [%s => %s]" % (env['PUBLIC_IP'], env['PUBLIC_HOSTNAME']))
	else:
		print_error("""Your box's reverse DNS is currently %s, but it should be %s. Your ISP or cloud provider will have instructions
			on setting up reverse DNS for your box at %s.""" % (existing_rdns, domain, env['PUBLIC_IP']) )

def check_dns_zone(domain, env, dns_zonefiles):
	# We provide a DNS zone for the domain. It should have NS records set up
	# at the domain name's registrar pointing to this box.
	existing_ns = query_dns(domain, "NS")
	correct_ns = "ns1.BOX; ns2.BOX".replace("BOX", env['PUBLIC_HOSTNAME'])
	if existing_ns == correct_ns:
		print_ok("Nameservers are set correctly at registrar. [%s]" % correct_ns)
	else:
		print_error("""The nameservers set on this domain are incorrect. They are currently %s. Use your domain name registar's
			control panel to set the nameservers to %s."""
				% (existing_ns, correct_ns) )

	# See if the domain's A record resolves to our PUBLIC_IP. This is already checked
	# for PUBLIC_HOSTNAME, for which it is required. For other domains it is just nice
	# to have if we want web.
	if domain != env['PUBLIC_HOSTNAME']:
		ip = query_dns(domain, "A")
		if ip == env['PUBLIC_IP']:
			print_ok("Domain resolves to this box's IP address. [%s => %s]" % (domain, env['PUBLIC_IP']))
		else:
			print_error("""This domain should resolve to your box's IP address (%s) if you would like the box to serve
				webmail or a website on this domain. The domain currently resolves to %s in public DNS. It may take several hours for
				public DNS to update after a change. This problem may result from other issues listed here.""" % (env['PUBLIC_IP'], ip))

	# See if the domain has a DS record set.
	ds = query_dns(domain, "DS", nxdomain=None)
	ds_correct = open('/etc/nsd/zones/' + dns_zonefiles[domain] + '.ds').read().strip()
	ds_expected = re.sub(r"\S+\.\s+3600\s+IN\s+DS\s*", "", ds_correct)
	if ds == ds_expected:
		print_ok("DNS 'DS' record is set correctly at registrar.")
	elif ds == None:
		print_error("""This domain's DNS DS record is not set. The DS record is optional. The DS record activates DNSSEC.
			To set a DS record, you must follow the instructions provided by your domain name registrar and provide to them this information:""")
		print("")
		print("   " + ds_correct)
		print("")
	else:
		print_error("""This domain's DNS DS record is incorrect. The chain of trust is broken between the public DNS system
			and this machine's DNS server. It may take several hours for public DNS to update after a change. If you did not recently
			make a change, you must resolve this immediately by following the instructions provided by your domain name registrar and
			provide to them this information:""")
		print("")
		print("   " + ds_correct)
		print("")

def check_mx(domain, env):
	# Check the MX record.
	mx = query_dns(domain, "MX")
	expected_mx = "10 " + env['PUBLIC_HOSTNAME']
	if mx == expected_mx:
		print_ok("Domain's email is directed to this domain. [%s => %s]" % (domain, mx))
	else:
		print_error("""This domain's DNS MX record is incorrect. It is currently set to '%s' but should be '%s'. Mail will not
			be delivered to this box. It may take several hours for public DNS to update after a change. This problem may result from
			other issues listed here.""" % (mx, expected_mx))

def query_dns(qname, rtype, nxdomain='[Not Set]'):
	resolver = dns.resolver.get_default_resolver()
	try:
		response = dns.resolver.query(qname, rtype)
	except dns.resolver.NoNameservers:
		# Could not reach nameserver.
		raise
	except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
		# Host did not have an answer for this query; not sure what the
		# difference is between the two exceptions.
		return nxdomain

	# There may be multiple answers; concatenate the response. Remove trailing
	# periods from responses since that's how qnames are encoded in DNS but is
	# confusing for us.
	return "; ".join(str(r).rstrip('.') for r in response)

def check_ssl_cert(domain, env):
	# Check that SSL certificate is signed.

	ssl_key, ssl_certificate, ssl_csr_path = get_domain_ssl_files(domain, env)

	if not os.path.exists(ssl_certificate):
		print_error("The SSL certificate file for this domain is missing.")
		return

	# Check that the certificate is good. In order to verify with openssl, we need to split out any
	# intermediary certificates in the chain (if any) from our certificate (at the top).

	cert = open(ssl_certificate).read()
	mycert, chaincerts = re.match(r'(-*BEGIN CERTIFICATE-*.*?-*END CERTIFICATE-*)(.*)', cert, re.S).groups()

	# This command returns a non-zero exit status in most cases, so trap errors.
	retcode, verifyoutput = shell('check_output', [
		"openssl",
		"verify", "-verbose",
		"-purpose", "sslserver", "-policy_check",]
		+ ([] if chaincerts.strip() == "" else ["-untrusted", "/dev/stdin"])
		+ [ssl_certificate],
		input=chaincerts.encode('ascii'),
		trap=True)

	if "self signed" in verifyoutput:
		fingerprint = shell('check_output', [
			"openssl",
			"x509",
			"-in", ssl_certificate,
			"-noout",
			"-fingerprint"
			])
		fingerprint = re.sub(".*Fingerprint=", "", fingerprint).strip()

		print_error("""The SSL certificate for this domain is currently self-signed. That's OK if you are willing to confirm security
			exceptions when you check your mail (either via IMAP or webmail), but if you are serving a website on this domain then users
			will not be able to access the site. When confirming security exceptions, check that the certificate fingerprint matches:""")
		print()
		print("   " + fingerprint)
		print()
		print_block("""You can purchase a signed certificate from many places. You will need to provide this Certificate Signing Request (CSR)
			to whoever you purchase the SSL certificate from:""")
		print()
		print(open(ssl_csr_path).read().strip())
		print()
		print_block("""When you purchase an SSL certificate you will receive a certificate in PEM format and possibly a file containing intermediate certificates in PEM format.
			If you receive intermediate certificates, use a text editor and paste your certificate on top and then the intermediate certificates
			below it. Save the file and place it onto this machine at %s.""" % ssl_certificate)


	elif retcode == 0:
		print_ok("SSL certificate is signed.")
	else:
		print_error("The SSL certificate has a problem:")
		print("")
		print(verifyoutput.strip())
		print("")

def print_ok(message):
	print_block(message, first_line="✓  ")

def print_error(message):
	print_block(message, first_line="✖  ")

def print_block(message, first_line="   "):
	print(first_line, end='')
	message = re.sub("\n\s*", " ", message)
	words = re.split("(\s+)", message)
	linelen = 0
	for w in words:
		if linelen + len(w) > 75:
			print()
			print("   ", end="")
			linelen = 0
		if linelen == 0 and w.strip() == "": continue
		print(w, end="")
		linelen += len(w)
	if linelen > 0:
		print()

if __name__ == "__main__":
	from utils import load_environment
	run_checks(load_environment())
