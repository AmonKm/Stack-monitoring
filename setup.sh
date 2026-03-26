#!/bin/bash
set -e

echo "=== Stack Monitoring — Setup ==="
echo ""

# 1. Vérifier les dépendances
command -v docker >/dev/null || { echo "Docker requis"; exit 1; }
command -v nmap >/dev/null || apt-get install -y nmap -qq

# 2. Créer .env si absent
if [ ! -f .env ]; then
    cp .env.example .env
    echo ".env créé depuis .env.example"
fi

# 3. Demander le subnet du SI
read -p "Subnet du SI (ex: 10.0.0.0/24) : " SUBNET
read -p "IP du firewall pfSense : " FW_IP
read -p "IP du honeypot : " HONEYPOT_IP

# 4. Scanner les node_exporters sur le réseau
echo ""
echo "Scan du réseau $SUBNET sur le port 9100..."
HOSTS=$(nmap -p 9100 --open -oG - $SUBNET 2>/dev/null | grep "9100/open" | awk '{print $2}')

if [ -z "$HOSTS" ]; then
    echo "Aucun node_exporter trouvé sur $SUBNET"
    echo "Vérifiez que node_exporter est installé sur les machines du SI"
    exit 1
fi

echo "Machines détectées :"
for HOST in $HOSTS; do
    echo "  - $HOST:9100"
done

# 5. Générer targets/si.yml
cat > prometheus/targets/si.yml << TARGETS
- targets:
$(for HOST in $HOSTS; do echo "    - \"$HOST:9100\""; done)
  labels:
    env: "si-principal"
    provisioned_by: "auto-discovery"
TARGETS

# 6. Générer targets/firewall.yml
cat > prometheus/targets/firewall.yml << TARGETS
- targets:
    - "$FW_IP:9100"
  labels:
    env: "si-principal"
    role: "firewall"
    type: "pfsense"
TARGETS

# 7. Générer targets/honeypot.yml
cat > prometheus/targets/honeypot.yml << TARGETS
- targets:
    - "$HONEYPOT_IP:9100"
  labels:
    env: "dmz"
    role: "honeypot"
TARGETS

echo ""
echo "Fichiers de targets générés :"
echo "  prometheus/targets/si.yml"
echo "  prometheus/targets/firewall.yml"
echo "  prometheus/targets/honeypot.yml"

# 8. Lancer la stack
echo ""
echo "Lancement de la stack..."
docker compose up -d

# 9. Recharger Prometheus si déjà lancé
sleep 5
curl -s -X POST http://localhost:9090/-/reload 2>/dev/null && echo "Prometheus rechargé"

echo ""
echo "Grafana    : http://localhost:3000"
echo "Prometheus : http://localhost:9090"
echo "MinIO      : http://localhost:9001"
