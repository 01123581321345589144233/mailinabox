#!/usr/bin/python3

import os, os.path, re

from flask import Flask, request, render_template, abort
app = Flask(__name__)

import auth, utils
from mailconfig import get_mail_users, add_mail_user, set_mail_password, remove_mail_user, get_mail_aliases, get_mail_domains, add_mail_alias, remove_mail_alias

env = utils.load_environment()

auth_service = auth.KeyAuthService()

@app.before_request
def require_auth_key():
	if not auth_service.is_authenticated(request):
		abort(401)

@app.errorhandler(401)
def unauthorized(error):
	return auth_service.make_unauthorized_response()

@app.route('/')
def index():
    return render_template('index.html')

# MAIL

@app.route('/mail/users')
def mail_users():
    return "".join(x+"\n" for x in get_mail_users(env))

@app.route('/mail/users/add', methods=['POST'])
def mail_users_add():
	return add_mail_user(request.form.get('email', ''), request.form.get('password', ''), env)

@app.route('/mail/users/password', methods=['POST'])
def mail_users_password():
	return set_mail_password(request.form.get('email', ''), request.form.get('password', ''), env)

@app.route('/mail/users/remove', methods=['POST'])
def mail_users_remove():
	return remove_mail_user(request.form.get('email', ''), env)

@app.route('/mail/aliases')
def mail_aliases():
    return "".join(x+"\t"+y+"\n" for x, y in get_mail_aliases(env))

@app.route('/mail/aliases/add', methods=['POST'])
def mail_aliases_add():
	return add_mail_alias(request.form.get('source', ''), request.form.get('destination', ''), env)

@app.route('/mail/aliases/remove', methods=['POST'])
def mail_aliases_remove():
	return remove_mail_alias(request.form.get('source', ''), env)

@app.route('/mail/domains')
def mail_domains():
    return "".join(x+"\n" for x in get_mail_domains(env))

# DNS

@app.route('/dns/update', methods=['POST'])
def dns_update():
	from dns_update import do_dns_update
	try:
		return do_dns_update(env)
	except Exception as e:
		return (str(e), 500)

@app.route('/dns/ds')
def dns_get_ds_records():
	from dns_update import get_ds_records
	try:
		return get_ds_records(env).replace("\t", " ") # tabs confuse godaddy
	except Exception as e:
		return (str(e), 500)

# WEB

@app.route('/web/update', methods=['POST'])
def web_update():
	from web_update import do_web_update
	return do_web_update(env)

# System

@app.route('/system/updates')
def show_updates():
	utils.shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])
	simulated_install = utils.shell("check_output", ["/usr/bin/apt-get", "-qq", "-s", "upgrade"])
	pkgs = []
	for line in simulated_install.split('\n'):
		if re.match(r'^Conf .*', line): continue # remove these lines, not informative
		line = re.sub(r'^Inst (.*) \[(.*)\] \((\S*).*', r'Updated Package Available: \1 (\3)', line) # make these lines prettier
		pkgs.append(line)
	return "\n".join(pkgs)

@app.route('/system/update-packages', methods=["POST"])
def do_updates():
	utils.shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])
	return utils.shell("check_output", ["/usr/bin/apt-get", "-y", "upgrade"], env={
		"DEBIAN_FRONTEND": "noninteractive"
	})

# APP

if __name__ == '__main__':
	if "DEBUG" in os.environ: app.debug = True

	if not app.debug:
		app.logger.addHandler(utils.create_syslog_handler())

	# For testing on the command line, you can use `curl` like so:
	#    curl --user $(</var/lib/mailinabox/api.key): http://localhost:10222/mail/users
	auth_service.write_key()

	# For testing in the browser, you can copy the API key that's output to the
	# debug console and enter that as the username
	app.logger.info('API key: ' + auth_service.key)

	app.run(port=10222)

