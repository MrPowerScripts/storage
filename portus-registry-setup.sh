#!/bin/bash

###                                                                                     ##
### This script will turn an Ubuntu 18.04/10 server into a docker registry with a GUI   ##
###                                                                                     ##

## MrPowerScripts ##
# Website: https://MrPowerScripts.com
# Discord: https://bit.ly/mrps-discord
# Patreon: https://bit.ly/mrps-patreon
# Sign up: https://bit.ly/mrps-mail-list
# Twitter: https://bit.ly/mrps-twitter

# This script was created thanks to a number of guides and other peoples efforts. Please check them out!
# https://www.objectif-libre.com/en/blog/2018/06/11/self-hosting-a-secure-docker-registry-with-portus/
# https://www.humankode.com/ssl/how-to-set-up-free-ssl-certificates-from-lets-encrypt-using-docker-and-nginx

# THis script is intended to be run on ubuntu 18.04 or 18.10. You must run it from the home directory (~).
# I was able to run the box fine on a $10 droplet from digital ocean.
# It will provision the enviroment, install an ssl cert from letsencrypt, and start the Portus registry service.
# You can login to your new docker registry at https://${your_domain}:3000. 
# You WILL NOT be able to connect through http. You must prefix your URL with HTTPS.
# You will be asked to create an admin account on first visit. If you have any issues join my Discord server.

# After you have the server set up you can create other user account, or use the admin account. 
# You will be able to login to your private registry using the docker client by pointing it to your domain.
# ex. docker login forestfiles.com

# From here you can interact with your private registry to push and pull images as you would on DockerHub.

# =====!!!!!!! IMPORTANT !!!!!!!=====
# Make sure to set these values. 
# If your server is on a subdomain (sub.forestfiles.com) that's fine
# The domain must be set up with a properly configured A Record that points to the server IP.
# You cannot use an IP address with this configuration. You must have a domain name. 
DOMAIN="forestfiles.com" 
EMAIL="email@gmail.com"

if [ "$DOMAIN" == "forestfiles.com" ]; then
  echo "you forgot to change the domain"
  exit
elif [ "$EMAIL" == "email@gmail.com" ]; then
  echo "you forgot to change the email"
  exit
fi

# We'll use this later
UBUNTU=$( lsb_release -r | awk '{ print $2 }' | sed 's/[.]//' )
sudo apt-get update && sudo apt-get install jq -y


if [ "$UBUNTU" == 1804 ]; then
  # Install Docker Normally
  sudo apt-get install \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common -y
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable" -y
  sudo apt-get update -y 
  sudo apt-get install docker-ce -y
elif [ "$UBUNTU" == 1810 ]; then
  # Install docker 18.10 - this is before they had a release for this version. hack required
  sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic test" -y
  sudo apt install docker-ce -y
else
 echo "This script was meant to be run on at least Ubuntu 18.04"
 exit
fi

# Install docker compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Portus
rm -rf /tmp/portus
git clone https://github.com/SUSE/Portus.git /tmp/portus
mv /tmp/portus/examples/compose ./portus

# Edit the portus files for our domain and SSL
(
cd portus || exit
docker-compose down -v
sed -i "s/172.17.0.1/${DOMAIN}/g" .env
sed -i "s/172.17.0.1/${DOMAIN}/g" nginx/nginx.conf
sed -i "s/portus.crt/fullchain.pem/g" nginx/nginx.conf
sed -i "s/portus.key/privkey.pem/g" nginx/nginx.conf
sed -i "s/portus.crt/fullchain.pem/g" registry/init
rm docker-compose.*
)

# We're getting all the config files into the right place
sudo mkdir -p /docker/letsencrypt-docker-nginx/src/letsencrypt/letsencrypt-site
cat << 'EOF' > ./portus/docker-compose.yml
version: "2"

services:
  portus:
    image: opensuse/portus:head
    environment:
      - PORTUS_MACHINE_FQDN_VALUE=${MACHINE_FQDN}
      - PORTUS_SECURITY_CLAIR_SERVER=http://clair:6060

      # DB. The password for the database should definitely not be here. You are
      # probably better off with Docker Swarm secrets.
      - PORTUS_DB_HOST=db
      - PORTUS_DB_DATABASE=PORTUS_production
      - PORTUS_DB_PASSWORD=${DATABASE_PASSWORD}
      - PORTUS_DB_POOL=5

      # Secrets. It can possibly be handled better with Swarm's secrets.
      - PORTUS_SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - PORTUS_KEY_PATH=/certificates/privkey.pem
      - PORTUS_PASSWORD=${PORTUS_PASSWORD}

      # SSL
      - PORTUS_PUMA_TLS_KEY=/certificates/privkey.pem
      - PORTUS_PUMA_TLS_CERT=/certificates/fullchain.pem

      # NGinx is serving the assets instead of Puma. If you want to change this,
      # uncomment this line.
      - RAILS_SERVE_STATIC_FILES=true
      
      # Other Config
      #- PORTUS_SIGNUP_ENABLED=false
      - PORTUS_ANONYMOUS_BROWSING_ENABLED=false
      - PORTUS_DELETE_ENABLED=true
    ports:
      - 3000:3000
    links:
      - db
    volumes:
      - ./secrets:/certificates:ro
      #- ./static:/srv/Portus/public

  background:
    image: opensuse/portus:head
    depends_on:
      - portus
      - db
    environment:
      # Theoretically not needed, but cconfig's been buggy on this...
      - CCONFIG_PREFIX=portus
      - PORTUS_MACHINE_FQDN_VALUE=${MACHINE_FQDN}
      - PORTUS_SECURITY_CLAIR_SERVER=http://clair:6060

      # DB. The password for the database should definitely not be here. You are
      # probably better off with Docker Swarm secrets.
      - PORTUS_DB_HOST=db
      - PORTUS_DB_DATABASE=PORTUS_production
      - PORTUS_DB_PASSWORD=${DATABASE_PASSWORD}
      - PORTUS_DB_POOL=5

      # Secrets. It can possibly be handled better with Swarm's secrets.
      - PORTUS_SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - PORTUS_KEY_PATH=/certificates/privkey.pem
      - PORTUS_PASSWORD=${PORTUS_PASSWORD}

      - PORTUS_BACKGROUND=true
      - PORTUS_SYNC_ENABLED=true
      - PORTUS_SYNC_STRATEGY=update-delete
    links:
      - db
    volumes:
      #- ./secrets:/certificates:ro
      - /etc/letsencrypt/live/dr.mrpowerscripts.com:/certificates

  db:
    image: library/mariadb:10.0.23
    command: mysqld --character-set-server=utf8 --collation-server=utf8_unicode_ci --init-connect='SET NAMES UTF8;' --innodb-flush-log-at-trx-commit=0
    environment:
      - MYSQL_DATABASE=PORTUS_production

      # Again, the password shouldn't be handled like this.
      - MYSQL_ROOT_PASSWORD=${DATABASE_PASSWORD}
    volumes:
      - ./mariadb:/var/lib/mysql

  registry:
    image: library/registry:2.6
    command: ["/bin/sh", "/etc/docker/registry/init"]
    environment:
      # Authentication
      REGISTRY_AUTH_TOKEN_REALM: https://${MACHINE_FQDN}/v2/token
      REGISTRY_AUTH_TOKEN_SERVICE: ${MACHINE_FQDN}:5000
      REGISTRY_AUTH_TOKEN_ISSUER: ${MACHINE_FQDN}
      REGISTRY_AUTH_TOKEN_ROOTCERTBUNDLE: /secrets/fullchain.pem

      # SSL
      REGISTRY_HTTP_TLS_CERTIFICATE: /secrets/fullchain.pem
      REGISTRY_HTTP_TLS_KEY: /secrets/privkey.pem

      # portus endpoint
      REGISTRY_NOTIFICATIONS_ENDPOINTS: >
        - name: portus
          url: https://${MACHINE_FQDN}/v2/webhooks/events
          timeout: 2000ms
          threshold: 5
          backoff: 1s
    volumes:
      - ./secrets:/usr/local/share/ca-certificates:ro
      - ./registry/data:/var/lib/registry
      - ./secrets:/secrets:ro
      - ./registry/config.yml:/etc/docker/registry/config.yml:ro
      - ./registry/init:/etc/docker/registry/init:ro
    ports:
      - 5000:5000
      - 5001:5001 # required to access debug service
    links:
      - portus:portus

  postgres:
    image: library/postgres:10-alpine
    environment:
      POSTGRES_PASSWORD: portus

  clair:
    image: quay.io/coreos/clair
    restart: unless-stopped
    depends_on:
      - postgres
    links:
      - postgres
      - portus
    ports:
      - "6060-6061:6060-6061"
    volumes:
      - /tmp:/tmp
      - ./clair/clair.yml:/clair.yml
    command: [-config, /clair.yml]


  nginx:
    image: library/nginx:alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./secrets:/secrets:ro
      - static:/srv/Portus/public:ro
    ports:
      - 80:80
      - 443:443
    links:
      - registry:registry
      - portus:portus


volumes:
  static:
EOF

cat << EOF > /docker/letsencrypt-docker-nginx/src/letsencrypt/docker-compose.yml
version: '3.1'

services:

  letsencrypt-nginx-container:
    container_name: 'letsencrypt-nginx-container'
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
      - ./letsencrypt-site:/usr/share/nginx/html
    networks:
      - docker-network

networks:
  docker-network:
    driver: bridge
EOF

cat << EOF > /docker/letsencrypt-docker-nginx/src/letsencrypt/nginx.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN}.com www.${DOMAIN}.com;

    location ~ /.well-known/acme-challenge {
        allow all;
        root /usr/share/nginx/html;
    }

    root /usr/share/nginx/html;
    index index.html;
}
EOF

# Bring up the nginx webserver to get the letsencrypt certs
cd /docker/letsencrypt-docker-nginx/src/letsencrypt || exit
sudo docker-compose up -d || exit

sleep 5

# Now we're getting the real cert here
sudo docker run --rm \
  -v /docker-volumes/etc/letsencrypt:/etc/letsencrypt \
  -v /docker-volumes/var/lib/letsencrypt:/var/lib/letsencrypt \
  -v /docker/letsencrypt-docker-nginx/src/letsencrypt/letsencrypt-site:/data/letsencrypt \
  -v "/docker-volumes/var/log/letsencrypt:/var/log/letsencrypt" \
  certbot/certbot \
  certonly --webroot \
  --email "${EMAIL}" --agree-tos --no-eff-email \
  --webroot-path=/data/letsencrypt \
  -d "${DOMAIN}"

# Copy our new cert to the portus secrets folder
cp /docker-volumes/etc/letsencrypt/live/"${DOMAIN}"/* ~/portus/secrets


# Shutdown the letsencrypt webserver
cd /docker/letsencrypt-docker-nginx/src/letsencrypt || exit
sudo docker-compose down

cd ~/portus || exit

docker-compose up -d --force-recreate

# ----------- this is all stuff to do a self signed cert
# Yuu have to do all kinda of weird client side stuff to connect to self signed certs tho
# echo "subjectAltName = URI:${DOMAIN}" > extfile.cnf
# echo "basicConstraints=CA:FALSE" >> extfile.cnf || exit
# echo "subjectAltName=@my_subject_alt_names" >> extfile.cnf || exit
# echo "subjectKeyIdentifier = hash" >> extfile.cnf || exit
# echo "[ my_subject_alt_names ]" >> extfile.cnf || exit
# echo "DNS.1 = *.${DOMAIN}" >> extfile.cnf || exit

# openssl genrsa -out secrets/rootca.key 2048
# dd if=/dev/urandom of=~/.rnd bs=256 count=1
# openssl req -x509 -new -nodes -key secrets/rootca.key \
#  -subj "/C=US/ST=CA/O=Acme, Inc." \
#  -sha256 -days 1024 -out secrets/rootca.crt

# openssl genrsa -out secrets/portus.key 2048
# openssl req -new -key secrets/portus.key -out secrets/portus.csr \
#  -subj "/C=US/ST=CA/O=Acme, Inc./CN=${DOMAIN}"

# openssl x509 -req -in secrets/portus.csr -CA secrets/rootca.crt -extfile \
#  extfile.cnf -CAkey secrets/rootca.key -CAcreateserial \
#  -out secrets/portus.crt -days 500 -sha256
