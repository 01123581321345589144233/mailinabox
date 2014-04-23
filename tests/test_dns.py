#!/usr/bin/python3
#
# Tests the DNS configuration of a Mail-in-a-Box.
#
# tests/dns.py ipaddr hostname
#
# where ipaddr is the IP address of your Mail-in-a-Box
# and hostname is the domain name to check the DNS for.

import sys, re, difflib
import dns.reversename, dns.resolver

if len(sys.argv) < 3:
	print("Usage: tests/dns.py ipaddress hostname")
	sys.exit(1)

ipaddr, hostname = sys.argv[1:]

def test(server, description):
	tests = [
		(hostname, "A", ipaddr),
		(hostname, "NS", "ns1.%s.;ns2.%s." % (hostname, hostname)),
		("ns1." + hostname, "A", ipaddr),
		("ns2." + hostname, "A", ipaddr),
		("www." + hostname, "A", ipaddr),
		(hostname, "MX", "10 " + hostname + "."),
		(hostname, "TXT", "\"v=spf1 mx -all\""),
		("mail._domainkey." + hostname, "TXT", "\"v=DKIM1; k=rsa; s=email; \" \"p=__KEY__\""),
	]
	return test2(tests, server, description)

def test_ptr(server, description):
	ipaddr_rev = dns.reversename.from_address(ipaddr)
	tests = [
		(ipaddr_rev, "PTR", hostname+'.'),
	]
	return test2(tests, server, description)

def test2(tests, server, description):
	first = True
	resolver = dns.resolver.get_default_resolver()
	resolver.nameservers = [server]
	for qname, rtype, expected_answer in tests:
		# do the query and format the result as a string
		response = dns.resolver.query(qname, rtype)
		response = ";".join(str(r) for r in response)
		response = re.sub(r"(\"p=).*(\")", r"\1__KEY__\2", response) # normalize DKIM key

		# is it right?
		if response == expected_answer:
			#print(server, ":", qname, rtype, "?", response)
			continue

		# show prolem
		if first:
			print("Incorrect DNS Response from", description)
			print()
			first = False

		print(qname, rtype, "got", repr(response), "but we should have gotten", repr(expected_answer))
	return first # success

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
