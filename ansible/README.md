## Intégration Ansible

Pour intégrer le monitoring dans un repo Ansible existant, copier `tasks/monitoring-client.yml` dans vos tâches et ajouter les variables suivantes dans `group_vars/all.yml` :
```yaml
monitoring_ip: "10.0.0.13"    # ← IP de votre VM monitoring
node_exporter_version: "1.10.2"
```

Puis inclure dans votre playbook :
```yaml
- name: Installer monitoring client
  include_tasks: tasks/monitoring-client.yml
```

Ce que ça installe automatiquement sur chaque VM :
- `node_exporter` (métriques système → Prometheus)
- `rsyslog` configuré pour envoyer les logs vers Loki
- Règle firewall `ufw` pour le port 9100
