# Stack Monitoring — Groupe 6.2

Stack de supervision basé sur **Prometheus + Loki + Grafana**, déployé sur une VM dédiée.  
Compatible avec toute infrastructure Linux disposant de `node_exporter` et `rsyslog`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Infrastructure (Groupe 6.1)              │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ pfsense  │  │   Mail   │  │   DNS    │  │   Web    │   │
│  │ :514/udp │  │ :514/udp │  │ :514/udp │  │ :514/udp │   │
│  │ node_exp │  │ node_exp │  │ node_exp │  │ node_exp │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
└───────┼─────────────┼─────────────┼──────────────┼─────────┘
        │  syslog UDP 514            │              │
        └────────────────────────────┘──────────────┘
                        │
        ┌───────────────▼──────────────────────────┐
        │            VM Monitoring                  │
        │                                          │
        │  rsyslog :514  →  /var/log/syslog-remote/│
        │                                          │
        │  ┌──────────┐  ┌──────────┐              │
        │  │ Promtail │  │  Prom.   │              │
        │  │ lit logs │  │scrape    │              │
        │  └────┬─────┘  │node_exp  │              │
        │       │        └────┬─────┘              │
        │  ┌────▼─────────────▼─────┐              │
        │  │         Loki           │              │
        │  │    (stockage logs)     │              │
        │  └────────────┬───────────┘              │
        │  ┌────────────▼───────────┐              │
        │  │        Grafana         │              │
        │  │   dashboards :3000     │              │
        │  └────────────────────────┘              │
        └──────────────────────────────────────────┘
```

### Composants

| Composant | Rôle | Port |
|-----------|------|------|
| **Prometheus** | Collecte les métriques (CPU, RAM, réseau, disque) via `node_exporter` | 9090 (local) |
| **Loki** | Stockage et indexation des logs | 3100 (local) |
| **Promtail** | Lit les fichiers de logs et les envoie à Loki | — |
| **Grafana** | Visualisation dashboards et alertes | 3000 |
| **rsyslog** | Reçoit les logs syslog UDP/514 et les écrit sur disque | 514 |

---

## Prérequis

### VM Monitoring
- Debian/Ubuntu
- Docker + Docker Compose
- rsyslog (`sudo apt install -y rsyslog`)
- 2 Go RAM minimum, 20 Go disque

### VMs supervisées (groupe 6.1)
- `node_exporter` installé sur chaque VM (voir `ansible/`)
- Syslog configuré pour envoyer vers l'IP de la VM monitoring sur le port 514 UDP

---

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/AmonKm/Stack-monitoring.git
cd Stack-monitoring
```

### 2. Configurer les variables

```bash
cp .env.example .env
nano .env   # adapter GF_ADMIN_PASSWORD
```

### 3. Configurer rsyslog

Installer et configurer rsyslog pour recevoir les logs distants :

```bash
# Installer rsyslog
sudo apt install -y rsyslog

# Créer les dossiers de logs
sudo mkdir -p /var/log/syslog-remote
sudo chmod 755 /var/log/syslog-remote

# Copier la config rsyslog
sudo cp docs/rsyslog.conf /etc/rsyslog.d/10-remote.conf

# Redémarrer rsyslog
sudo systemctl restart rsyslog
sudo systemctl enable rsyslog
```

> **Adapter** le fichier `docs/rsyslog.conf` si le hostname de votre pfsense est différent de `pfSense.home.arpa`.

### 4. Adapter les targets Prometheus

Créer un fichier par VM dans `prometheus/targets/` :

```bash
# Exemple : prometheus/targets/hosts.yml
cat > prometheus/targets/hosts.yml << EOF
- targets:
    - "10.0.0.10:9100"   # web
    - "10.0.0.11:9100"   # mail
    - "10.0.0.12:9100"   # dns
    - "10.0.0.13:9100"   # monitoring
  labels:
    job: node
EOF
```

### 5. Lancer le stack

```bash
docker compose up -d
```

Vérifier que tout tourne :

```bash
docker compose ps
```

### 6. Accéder à Grafana

Ouvrir `http://<IP_VM_MONITORING>:3000`  
Login : `admin` / mot de passe défini dans `.env`

---

## Intégration pfsense

Dans l'interface web pfsense :  
**Status → System Logs → Settings**

| Paramètre | Valeur |
|-----------|--------|
| Enable Remote Logging | ✅ coché |
| Remote log servers | `<IP_VM_MONITORING>:514` |
| Remote Syslog Contents | Firewall Events + System Events |
| Log message format | RFC 5424 |

---

## Intégration VMs Linux (mail, web, dns)

Sur chaque VM à superviser, ajouter dans `/etc/rsyslog.conf` ou `/etc/rsyslog.d/forward.conf` :

```
*.* @<IP_VM_MONITORING>:514    # UDP
# ou
*.* @@<IP_VM_MONITORING>:514   # TCP
```

Puis :

```bash
sudo systemctl restart rsyslog
```

---

## Intégration node_exporter (métriques)

Déployer `node_exporter` via Ansible (voir `ansible/`) ou manuellement :

```bash
# Sur chaque VM supervisée
sudo apt install -y prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

Puis ajouter l'IP dans `prometheus/targets/hosts.yml`.

---

## Variables à adapter selon l'infra

| Fichier | Variable | Description |
|---------|----------|-------------|
| `.env` | `GF_ADMIN_PASSWORD` | Mot de passe Grafana |
| `.env` | `PROMETHEUS_RETENTION` | Durée de rétention métriques (défaut: 30d) |
| `docs/rsyslog.conf` | `pfSense.home.arpa` | Hostname de votre pfsense |
| `prometheus/targets/hosts.yml` | IPs | IPs des VMs avec node_exporter |
| `promtail/promtail-config.yml` | `__path__` | Chemins des fichiers de logs |

---

## Structure du dépôt

```
Stack-monitoring/
├── docker-compose.yml          # Stack principal
├── .env.example                # Variables à copier en .env
├── prometheus/
│   ├── prometheus.yml          # Config Prometheus
│   ├── targets/                # Fichiers de targets (hosts.yml)
│   └── rules/                  # Règles d'alerting
├── loki/
│   └── loki-config.yml         # Config Loki (filesystem)
├── promtail/
│   └── promtail-config.yml     # Config Promtail (sources de logs)
├── grafana/
│   ├── provisioning/           # Datasources et dashboards auto
│   └── dashboards/             # Fichiers JSON des dashboards
├── ansible/                    # Playbooks pour node_exporter
└── docs/
    └── rsyslog.conf            # Config rsyslog à copier sur la VM
```

---

## Dépannage

**Grafana inaccessible** → vérifier `docker compose ps` et les logs `docker logs grafana`

**Pas de métriques** → vérifier que `node_exporter` tourne sur les VMs (`curl http://<IP>:9100/metrics`)

**Pas de logs pfsense** → vérifier que rsyslog reçoit (`sudo tcpdump -i any udp port 514 -n`) et que les fichiers se créent dans `/var/log/syslog-remote/pfsense/`

**Loki erreur `empty ring`** → normal au démarrage, disparaît après ~30s

---

## Auteurs

Groupe 6.2 — Projet supervision infrastructure
