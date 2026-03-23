# Intégration monitoring — ce que JB doit ajouter

## 1. Copier notre rôle dans leur repo
```bash
cp -r monitoring/ansible/roles/monitoring-client SAE-601/Ansible/roles/
```

## 2. Ajouter dans leur `group_vars/all.yml`
```yaml
# IP de la VM monitoring
monitoring_ip: "10.0.0.50"
```

## 3. Ajouter dans leur `playbooks/site.yml`
```yaml
    - name: Installer monitoring client
      include_role:
        name: monitoring-client
      when: category != "firewall"
```

## 4. Pour pfSense — configurer le syslog
Dans l'interface pfSense :
Status → System Logs → Settings → Remote Logging
→ Remote log servers : 10.0.0.50:514

## Résultat
- node_exporter installé sur dns-01, dhcp-01, web-01, mail-01
- rsyslog configuré pour envoyer les logs vers Promtail
- Prometheus détecte automatiquement toutes les machines
- Grafana affiche les métriques sans intervention manuelle
