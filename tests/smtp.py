import smtplib, sys, os

fromaddr = "testuser@testdomain.com"

msg = """From: %s
To: %s

This is a test message.""" % (fromaddr, sys.argv[1])

server = smtplib.SMTP(os.environ["INSTANCE_IP"], 587)
server.set_debuglevel(1)
server.starttls()
server.login("testuser@testdomain.com", "testpw")
server.sendmail(fromaddr, [sys.argv[1]], msg)
server.quit()

