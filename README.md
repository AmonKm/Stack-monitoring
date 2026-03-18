# Stack Monitoring — Projet 6.2

## Composants
- **Prometheus** — collecte métriques (CPU, RAM, disque, réseau, DNS, mail)
- **Loki** — stockage logs structurés (syslog, auth, honeypot JSON)
- **Grafana** — dashboards et alertes

## Démarrage rapide
```bash
cp .env.example .env       # adapter les variables
docker compose up -d
```

## Intégration groupe 1 (IaC)
Voir `ansible/` — rôle `node_exporter` à intégrer dans leur playbook.
Les targets Prometheus sont dans `prometheus/targets/` et générées par Ansible.

## Intégration groupe 3 (Honeypot)
Promtail lit les logs JSON Cowrie dans `/var/log/cowrie/cowrie.json`.
Push vers Loki sur le port 3100.

## Ports exposés
| Service    | Port  | Usage                    |
|------------|-------|--------------------------|
| Grafana    | 3000  | Interface web            |
| Prometheus | 9090  | UI + API (localhost only)|
| Loki       | 3100  | Réception logs           |
