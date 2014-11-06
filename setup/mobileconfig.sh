#!/bin/bash
#
# iOS Configuration Profile
# ----------------------------------------------
#
# Mobileconfig for iOS users to setup IMAP, Contacts & Calendars
#
# https://developer.apple.com/library/ios/featuredarticles/iPhoneConfigurationProfileRef/Introduction/Introduction.html

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

echo "Generate iOS Configuration Profile"

echo "<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>CalDAVAccountDescription</key>
      <string>$PRIMARY_HOSTNAME calendar</string>
      <key>CalDAVHostName</key>
      <string>$PRIMARY_HOSTNAME</string>
      <key>CalDAVPort</key>
      <real>443</real>
      <key>CalDAVPrincipalURL</key>
      <string>/cloud/remote.php/caldav/calendars/</string>
      <key>CalDAVUseSSL</key>
      <true/>
      <key>PayloadDescription</key>
      <string>$PRIMARY_HOSTNAME (Mail-in-a-Box)</string>
      <key>PayloadDisplayName</key>
      <string>$PRIMARY_HOSTNAME calendar</string>
      <key>PayloadIdentifier</key>
      <string>email.mailinabox.mobileconfig.$PRIMARY_HOSTNAME.CalDAV</string>
      <key>PayloadOrganization</key>
      <string></string>
      <key>PayloadType</key>
      <string>com.apple.caldav.account</string>
      <key>PayloadUUID</key>
      <string>$(cat /proc/sys/kernel/random/uuid)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>EmailAccountDescription</key>
      <string>$PRIMARY_HOSTNAME mail</string>
      <key>EmailAccountType</key>
      <string>EmailTypeIMAP</string>
      <key>IncomingMailServerAuthentication</key>
      <string>EmailAuthPassword</string>
      <key>IncomingMailServerHostName</key>
      <string>$PRIMARY_HOSTNAME</string>
      <key>IncomingMailServerPortNumber</key>
      <integer>993</integer>
      <key>IncomingMailServerUseSSL</key>
      <true/>
      <key>OutgoingMailServerAuthentication</key>
      <string>EmailAuthPassword</string>
      <key>OutgoingMailServerHostName</key>
      <string>$PRIMARY_HOSTNAME</string>
      <key>OutgoingMailServerPortNumber</key>
      <integer>587</integer>
      <key>OutgoingMailServerUseSSL</key>
      <true/>
      <key>OutgoingPasswordSameAsIncomingPassword</key>
      <true/>
      <key>PayloadDescription</key>
      <string>$PRIMARY_HOSTNAME (Mail-in-a-Box)</string>
      <key>PayloadDisplayName</key>
      <string>$PRIMARY_HOSTNAME mail</string>
      <key>PayloadIdentifier</key>
      <string>email.mailinabox.mobileconfig.$PRIMARY_HOSTNAME.E-Mail</string>
      <key>PayloadOrganization</key>
      <string></string>
      <key>PayloadType</key>
      <string>com.apple.mail.managed</string>
      <key>PayloadUUID</key>
      <string>$(cat /proc/sys/kernel/random/uuid)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PreventAppSheet</key>
      <false/>
      <key>PreventMove</key>
      <false/>
      <key>SMIMEEnabled</key>
      <false/>
    </dict>
    <dict>
      <key>CardDAVAccountDescription</key>
      <string>$PRIMARY_HOSTNAME contacts</string>
      <key>CardDAVHostName</key>
      <string>$PRIMARY_HOSTNAME</string>
      <key>CardDAVPort</key>
      <integer>443</integer>
      <key>CardDAVPrincipalURL</key>
      <string>/cloud/remote.php/carddav/addressbooks/</string>
      <key>CardDAVUseSSL</key>
      <true/>
      <key>PayloadDescription</key>
      <string>$PRIMARY_HOSTNAME (Mail-in-a-Box)</string>
      <key>PayloadDisplayName</key>
      <string>$PRIMARY_HOSTNAME contacts</string>
      <key>PayloadIdentifier</key>
      <string>email.mailinabox.mobileconfig.$PRIMARY_HOSTNAME.carddav</string>
      <key>PayloadOrganization</key>
      <string></string>
      <key>PayloadType</key>
      <string>com.apple.carddav.account</string>
      <key>PayloadUUID</key>
      <string>$(cat /proc/sys/kernel/random/uuid)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDescription</key>
  <string>$PRIMARY_HOSTNAME (Mail-in-a-Box)</string>
  <key>PayloadDisplayName</key>
  <string>$PRIMARY_HOSTNAME</string>
  <key>PayloadIdentifier</key>
  <string>email.mailinabox.mobileconfig.$PRIMARY_HOSTNAME</string>
  <key>PayloadOrganization</key>
  <string></string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$(cat /proc/sys/kernel/random/uuid)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>" > "/var/lib/mailinabox/mobileconfig.xml";
