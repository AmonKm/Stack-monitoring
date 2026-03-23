#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "==> Mise à jour système"
apt-get update -qq

echo "==> Installation dépendances"
apt-get install -y -qq ca-certificates curl gnupg git

echo "==> Ajout dépôt Docker officiel"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "==> Installation Docker"
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "==> Ajout vagrant au groupe docker"
usermod -aG docker vagrant

echo "==> Installation node_exporter"
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar xzf node_exporter-1.10.2.linux-amd64.tar.gz
mv node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.10.2.linux-amd64*

cat > /etc/systemd/system/node_exporter.service << 'SERVICE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now node_exporter

echo "==> Copie des fichiers de configuration"
mkdir -p /opt/monitoring

# cp -r /vagrant/* ne copie pas les fichiers cachés (commence par .)
# on utilise rsync ou cp avec le bon glob
cp -r /vagrant/. /opt/monitoring/

cd /opt/monitoring

echo "==> Création du .env"
cp .env.example .env

echo "==> Lancement de la stack"
docker compose up -d

echo "==> Lancement du SI simulé"
cd /opt/monitoring/si-simulator
docker compose up -d

echo ""
echo "=========================================="
echo "  Stack monitoring opérationnelle"
echo "  Grafana   : http://localhost:3000"
echo "  Prometheus: http://localhost:9090"
echo "  Loki      : http://localhost:3100"
echo "=========================================="
