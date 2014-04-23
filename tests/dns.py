#!/usr/bin/python3
#
# Tests the DNS configuration of a Mail-in-a-Box.
#
# tests/dns.py ipaddr hostname
#
# where ipaddr is the IP address of your Mail-in-a-Box
# and hostname is the domain name to check the DNS for.

import sys, subprocess, re, difflib

if len(sys.argv) < 3:
	print("Usage: tests/dns.py ipaddress hostname")
	sys.exit(1)

ipaddr, hostname = sys.argv[1:]

# construct the expected output
subs = { "ipaddr": ipaddr, "hostname": hostname }
expected = """
{hostname}.	#####	IN	A	{ipaddr}
{hostname}.	#####	IN	NS	ns1.{hostname}.
{hostname}.	#####	IN	NS	ns2.{hostname}.
ns1.{hostname}.	#####	IN	A	{ipaddr}
ns2.{hostname}.	#####	IN	A	{ipaddr}
www.{hostname}.	#####	IN	A	{ipaddr}
{hostname}.	#####	IN	MX	10 {hostname}.
{hostname}.	#####	IN	TXT	"v=spf1 mx -all"
mail._domainkey.{hostname}. ##### IN TXT	"v=DKIM1\; k=rsa\; s=email\; " "p=__KEY__"
""".format(**subs).strip() + "\n"

def dig(server, digargs):
	# run dig and clean the output
	response = subprocess.check_output(['dig', '@' + server, "+noadditional", "+noauthority"] + digargs).decode('utf8')
	response = re.sub('[\r\n]+', '\n', response) # remove blank lines
	response = re.sub('\n;.*', '', response) # remove comments
	response = re.sub('(\n\S+\s+)(\d+)', r'\1#####', response) # normalize TTLs
	response = re.sub(r"(\"p=).*(\")", r"\1__KEY__\2", response) # normalize DKIM key
	response = response.strip() + "\n"
	return response

def test(server, description):
	digoutput = \
	   dig(server, [hostname])\
	 + dig(server, ["ns", hostname]) \
	 + dig(server, ["ns1." + hostname]) \
	 + dig(server, ["ns2." + hostname]) \
	 + dig(server, ["www." + hostname]) \
	 + dig(server, ["mx", hostname]) \
	 + dig(server, ["txt", hostname]) \
	 + dig(server, ["txt", "mail._domainkey." + hostname])
	return test2(digoutput, server, description, expected)

def test_ptr(server, description):
	ipaddr_reversed = ".".join( reversed( ipaddr.split(".") ) )
	expected = "%s.in-addr.arpa. ##### IN	PTR	%s.\n" % (ipaddr_reversed, hostname)
	digoutput = dig(server, ["-x", ipaddr])
	return test2(digoutput, server, description, expected)

def test2(digoutput, server, description, expected):
	# Show a diff if there are any changes
	has_diff = False
	def split(s): return [line+"\n" for line in s.split("\n")]
	for line in difflib.unified_diff(split(expected), split(digoutput), fromfile='expected DNS settings', tofile=description):
		if not has_diff:
			print("The response from %s (%s) is not correct:" % (description, server))
			print()
		has_diff = True
		sys.stdout.write(line)
	return not has_diff

# Test the response from the machine itself.
if not test(ipaddr, "Mail-in-a-Box"):
	print ()
	print ("Please run the Mail-in-a-Box setup script on %s again." % hostname)
	sys.exit(1)
else:
	# If those settings are OK, also test Google's Public DNS
	# to see if the machine is hooked up to recursive DNS properly.
	if not test("8.8.8.8", "Google Public DNS"):
		print ()
		print ("Check that the nameserver settings for %s are correct at your domain registrar. It may take a few hours for Google Public DNS to update after changes on your Mail-in-a-Box." % hostname)
		sys.exit(1)
	else:
		# And if that's OK, also check reverse DNS (the PTR record).
		if not test_ptr("8.8.8.8", "Google Public DNS (Reverse DNS)"):
			print ()
			print ("The reverse DNS for %s is not correct. Consult your ISP for how to set the reverse DNS (also called the PTR record) for %s to %s." % (hostname, hostname, ipaddr))
			sys.exit(1)
		else:
			print ("DNS is OK.")
