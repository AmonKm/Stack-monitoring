#!/bin/bash
# =============================================================================
# Stack Monitoring — Script de configuration interactif
# Ce script configure automatiquement le stack selon votre infrastructure
# =============================================================================
 
set -e
 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
 
print_banner() {
  echo -e "${CYAN}"
  echo "=============================================="
  echo "   Stack Monitoring — Configuration"
  echo "   Prometheus + Loki + Grafana"
  echo "=============================================="
  echo -e "${NC}"
}
 
print_step() {
  echo -e "\n${BLUE}==>${NC} $1"
}
 
print_ok() {
  echo -e "  ${GREEN}✔${NC} $1"
}
 
print_warn() {
  echo -e "  ${YELLOW}⚠${NC} $1"
}
 
print_error() {
  echo -e "  ${RED}✘${NC} $1"
}
 
ask() {
  echo -e -n "  ${CYAN}?${NC} $1 : "
  read -r answer
  echo "$answer"
}
 
ask_default() {
  echo -e -n "  ${CYAN}?${NC} $1 [${YELLOW}$2${NC}] : "
  read -r answer
  echo "${answer:-$2}"
}
 
confirm() {
  echo -e -n "  ${CYAN}?${NC} $1 [y/N] : "
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
 
# =============================================================================
# VÉRIFICATIONS PRÉALABLES
# =============================================================================
 
check_prerequisites() {
  print_step "Vérification des prérequis"
 
  if ! command -v docker &>/dev/null; then
    print_error "Docker n'est pas installé."
    echo "    Installer Docker : https://docs.docker.com/engine/install/"
    exit 1
  fi
  print_ok "Docker installé : $(docker --version | cut -d' ' -f3 | tr -d ',')"
 
  if ! docker compose version &>/dev/null; then
    print_error "Docker Compose n'est pas disponible."
    exit 1
  fi
  print_ok "Docker Compose installé"
 
  if ! command -v rsyslog &>/dev/null && ! systemctl is-active rsyslog &>/dev/null; then
    print_warn "rsyslog ne semble pas installé. Installation..."
    sudo apt-get install -y rsyslog
  fi
  print_ok "rsyslog disponible"
}
 
# =============================================================================
# COLLECTE DES INFORMATIONS
# =============================================================================
 
collect_info() {
  print_step "Configuration de l'infrastructure"
  echo ""
 
  # IP VM monitoring
  MONITORING_IP=$(ask_default "IP de cette VM monitoring" "10.0.0.13")
 
  # Mot de passe Grafana
  GRAFANA_PASSWORD=$(ask_default "Mot de passe Grafana" "changeme")
 
  # Rétention Prometheus
  PROMETHEUS_RETENTION=$(ask_default "Rétention métriques Prometheus" "30d")
 
  echo ""
  print_step "Configuration des VMs à superviser"
  echo "    Entrer les IPs des VMs (laisser vide pour ignorer)"
  echo ""
 
  VM_DNS=$(ask_default "IP VM DNS" "")
  VM_DHCP=$(ask_default "IP VM DHCP" "")
  VM_WEB=$(ask_default "IP VM Web" "")
  VM_MAIL=$(ask_default "IP VM Mail" "")
  VM_FIREWALL=$(ask_default "IP Firewall pfsense" "")
 
  echo ""
  print_step "Configuration pfsense (logs)"
  PFSENSE_HOSTNAME=$(ask_default "Hostname pfsense (pour rsyslog)" "pfSense.home.arpa")
 
  echo ""
  print_step "Résumé de la configuration"
  echo ""
  echo "  VM Monitoring     : $MONITORING_IP"
  echo "  Grafana password  : $GRAFANA_PASSWORD"
  echo "  Rétention         : $PROMETHEUS_RETENTION"
  echo "  VM DNS            : ${VM_DNS:-non configuré}"
  echo "  VM DHCP           : ${VM_DHCP:-non configuré}"
  echo "  VM Web            : ${VM_WEB:-non configuré}"
  echo "  VM Mail           : ${VM_MAIL:-non configuré}"
  echo "  Firewall          : ${VM_FIREWALL:-non configuré}"
  echo "  Hostname pfsense  : $PFSENSE_HOSTNAME"
  echo ""
 
  if ! confirm "Confirmer et lancer la configuration ?"; then
    echo "Configuration annulée."
    exit 0
  fi
}
 
# =============================================================================
# GÉNÉRATION DU .env
# =============================================================================
 
generate_env() {
  print_step "Génération du fichier .env"
 
  cat > .env << EOF
GF_ADMIN_USER=admin
GF_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
PROMETHEUS_RETENTION=${PROMETHEUS_RETENTION}
EOF
 
  print_ok ".env généré"
}
 
# =============================================================================
# GÉNÉRATION DES TARGETS PROMETHEUS
# =============================================================================
 
generate_prometheus_targets() {
  print_step "Génération des targets Prometheus"
 
  mkdir -p prometheus/targets
 
  # monitoring lui-même
  cat > prometheus/targets/monitoring.yml << EOF
- targets:
    - "${MONITORING_IP}:9100"
  labels:
    env: "si-principal"
    role: "monitoring"
EOF
  print_ok "Target monitoring : $MONITORING_IP"
 
  # VMs SI
  SI_TARGETS=""
  add_target() {
    local ip=$1
    local role=$2
    if [ -n "$ip" ]; then
      SI_TARGETS="${SI_TARGETS}
- targets:
    - \"${ip}:9100\"
  labels:
    env: \"si-principal\"
    role: \"${role}\"
    provisioned_by: \"ansible\"
"
      print_ok "Target $role : $ip"
    fi
  }
 
  add_target "$VM_DNS" "dns"
  add_target "$VM_DHCP" "dhcp"
  add_target "$VM_WEB" "web"
  add_target "$VM_MAIL" "mail"
 
  if [ -n "$SI_TARGETS" ]; then
    echo "$SI_TARGETS" > prometheus/targets/si.yml
  fi
 
  # Firewall
  if [ -n "$VM_FIREWALL" ]; then
    cat > prometheus/targets/firewall.yml << EOF
- targets:
    - "${VM_FIREWALL}:9100"
  labels:
    env: "si-principal"
    role: "firewall"
    type: "pfsense"
EOF
    print_ok "Target firewall : $VM_FIREWALL"
  fi
 
  # prometheus.yml — remplacer l'IP monitoring
  sed -i "s|10\.0\.0\.13:9100|${MONITORING_IP}:9100|g" prometheus/prometheus.yml
  print_ok "prometheus.yml mis à jour"
}
 
# =============================================================================
# CONFIGURATION RSYSLOG
# =============================================================================
 
configure_rsyslog() {
  print_step "Configuration de rsyslog"
 
  sudo mkdir -p /var/log/syslog-remote
  sudo chmod 755 /var/log/syslog-remote
 
  # Adapter le hostname pfsense dans la config rsyslog
  RSYSLOG_CONF="docs/rsyslog.conf"
  if [ -f "$RSYSLOG_CONF" ]; then
    TEMP_CONF=$(mktemp)
    sed "s|pfSense\.home\.arpa|${PFSENSE_HOSTNAME}|g" "$RSYSLOG_CONF" > "$TEMP_CONF"
    sudo cp "$TEMP_CONF" /etc/rsyslog.d/00-promtail-relay.conf
    rm "$TEMP_CONF"
    print_ok "Config rsyslog copiée avec hostname : $PFSENSE_HOSTNAME"
  else
    print_warn "docs/rsyslog.conf introuvable, rsyslog non configuré"
  fi
 
  sudo systemctl restart rsyslog
  sudo systemctl enable rsyslog
  print_ok "rsyslog redémarré"
}
 
# =============================================================================
# ADAPTATION PROMTAIL
# =============================================================================
 
configure_promtail() {
  print_step "Adaptation de la config Promtail"
 
  echo ""
  print_warn "Les logs des VMs seront reçus dans /var/log/syslog-remote/"
  print_warn "Les dossiers sont créés automatiquement par rsyslog selon les hostnames."
  print_warn "Après le premier démarrage, vérifier :"
  echo "    ls /var/log/syslog-remote/"
  print_warn "Puis adapter promtail/promtail-config.yml si les hostnames diffèrent."
  echo ""
}
 
# =============================================================================
# INSTALLATION NODE_EXPORTER (optionnel)
# =============================================================================
 
install_node_exporter() {
  if command -v prometheus-node-exporter &>/dev/null || systemctl is-active prometheus-node-exporter &>/dev/null 2>/dev/null; then
    print_ok "node_exporter déjà installé"
    return
  fi
 
  print_step "Installation de node_exporter"
 
  if confirm "Installer node_exporter sur cette VM ?"; then
    sudo apt-get install -y prometheus-node-exporter
    sudo systemctl enable --now prometheus-node-exporter
    print_ok "node_exporter installé et démarré"
  fi
}
 
# =============================================================================
# LANCEMENT DU STACK
# =============================================================================
 
launch_stack() {
  print_step "Lancement du stack Docker"
 
  docker compose up -d
 
  echo ""
  print_ok "Stack démarré !"
  echo ""
  echo -e "  ${GREEN}Grafana    :${NC} http://${MONITORING_IP}:3000"
  echo -e "  ${GREEN}Login      :${NC} admin / ${GRAFANA_PASSWORD}"
  echo -e "  ${GREEN}Prometheus :${NC} http://${MONITORING_IP}:9090 (local)"
  echo -e "  ${GREEN}Loki       :${NC} http://${MONITORING_IP}:3100 (local)"
  echo ""
}
 
# =============================================================================
# VÉRIFICATIONS FINALES
# =============================================================================
 
check_stack() {
  print_step "Vérification du stack"
  sleep 10
 
  SERVICES=("prometheus" "loki" "promtail" "grafana")
  for svc in "${SERVICES[@]}"; do
    STATUS=$(docker compose ps "$svc" --format "{{.Status}}" 2>/dev/null || echo "inconnu")
    if echo "$STATUS" | grep -qi "up\|running\|healthy"; then
      print_ok "$svc : opérationnel"
    else
      print_warn "$svc : $STATUS"
    fi
  done
 
  echo ""
  print_step "Vérification des targets Prometheus"
  sleep 5
  TARGETS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | grep -o '"health":"up"' | wc -l)
  print_ok "$TARGETS target(s) Prometheus actives"
}
 
# =============================================================================
# MAIN
# =============================================================================
 
main() {
  print_banner
  check_prerequisites
  collect_info
  generate_env
  generate_prometheus_targets
  configure_rsyslog
  configure_promtail
  install_node_exporter
  launch_stack
  check_stack
 
  echo ""
  echo -e "${GREEN}=============================================="
  echo "  Configuration terminée !"
  echo "  Consulter le README.md pour la suite"
  echo -e "==============================================${NC}"
  echo ""
}
 
main
