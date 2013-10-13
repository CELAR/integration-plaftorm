# ~/Nexus-cert.crt on Nexus server is /etc/ssl/certs/server.crt

# just in case
update-alternatives --config keytool

keytool -importcert -alias "celar-nexus" -file ~/Jenkins-install/Nexus-cert.crt -keystore /etc/ssl/certs/java/cacerts
# Default password 'changeit'
  