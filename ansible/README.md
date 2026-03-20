# Intégration monitoring — instructions groupe 6.1

## Ce que ça fait
Ce rôle Ansible installe automatiquement le client monitoring sur chaque machine :
- node_exporter (métriques système) pour prometheus
- rsyslog configuré pour envoyer les logs vers Promtail
- Firewall : port 9100 ouvert uniquement vers la VM monitoring

## Utilisation

### 1. Adapter l'inventaire
Copier `inventory.example.yml` → `inventory.yml`
Remplacer les IPs par les vraies IPs de votre infra Terraform/Ansible.

### 2. Définir l'IP de la VM monitoring
Dans `inventory.yml`, mettre la vraie IP de la VM monitoring :
```yaml
monitoring_ip: "192.168.10.50"   # IP de la VM monitoring
```

### 3. Exécuter
```bash
ansible-playbook -i inventory.yml deploy-monitoring-client.yml
```

### 4. Résultat
- Prometheus détecte automatiquement les nouvelles machines
- Les logs arrivent dans Loki via rsyslog
- Grafana affiche tout sans intervention manuelle

## Ports requis
| Port | Proto | Direction | Usage |
|------|-------|-----------|-------|
| 9100 | TCP | machines → monitoring | node_exporter |
| 514  | UDP | machines → monitoring | syslog |
| 3000 | TCP | réseau → monitoring | Grafana UI |
