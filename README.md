![Stack](https://img.shields.io/badge/stack-Prometheus%20%7C%20Loki%20%7C%20Grafana-orange)
![Docker](https://img.shields.io/badge/docker-compose-blue)
# Stack Monitoring - Groupe 6.2

Stack de supervision **Prometheus + Loki + Grafana** déployable sur n'importe quelle infrastructure Linux.  
Un `git clone` + 3 commandes suffisent pour avoir un monitoring complet opérationnel.

---
## Démarrage rapide
```bash
git clone https://github.com/AmonKm/Stack-monitoring.git
cd Stack-monitoring
chmod +x setup.sh
sudo ./setup.sh
```

Le script configure automatiquement l'ensemble du stack en mode interactif :
il demande les IPs de vos VMs, le mot de passe Grafana, le hostname pfsense,
génère tous les fichiers de configuration et lance Docker Compose.

> Pour une configuration manuelle détaillée, consulter la section [Installation rapide](#installation-rapide) ci-dessous.
---
## Architecture
```
Infrastructure cible (groupe 6.1)
──────────────────────────────────────────────────────────────────
 pfSense     Mail      DHCP      DNS       Web      monitoring
    │           │         │        │         │           │
    │     syslog UDP :1514 (tous les hosts)  │           │ journald
    └───────────┴─────────┴────────┴─────────┘           │
                          │                               │
    ┌─────────────────────┼───────────────────────────────┘
    │  node_exporter :9100 (tous les hosts)
    └──────────────────────────────────────────────────────
──────────────────────────────────────────────────────────────────
VM monitoring (groupe 6.2)

  [LOGS]                              [MÉTRIQUES]

  rsyslog :1514                       Prometheus
  (reçoit syslog UDP)                 (scrape :9100)
       │                                    │
       │ écrit par host                     │ stocke TSDB
       ▼                                    │
  /var/log/syslog-remote/                   │
    ├── pfSense.home.arpa/                  │
    ├── mail-01/                            │
    ├── dhcp-01/                            │
    ├── dns-01/                             │
    └── web-01/                             │
       │                                    │
       │ lit (tail -f)                      │
       ▼                                    │
    Promtail                                │
       │                                    │
       │ push HTTP :3100                    │
       ▼                                    │
      Loki                                  │
       │                                    │
       │ stocke (S3)                        │
       ▼                                    │
     MinIO                                  │
                                            │
──────────────────────────────────────────────────────────────────
              Grafana :3000
         ┌────────┴────────┐
        Loki           Prometheus
     (LogQL)           (PromQL)
```
## Composants

| Composant | Rôle | Port |
|-----------|------|------|
| **Prometheus** | Collecte métriques CPU/RAM/disque/réseau via `node_exporter` | 9090 (local) |
| **Loki** | Stockage et indexation des logs | 3100 (local) |
| **Promtail** | Lit les fichiers de logs → pousse vers Loki | interne |
| **Grafana** | Dashboards et alertes | 3000 |
| **rsyslog** | Reçoit logs syslog UDP/514 → écrit sur disque | 514 |

---

## Prérequis

### VM Monitoring
- OS : Debian 12 / Ubuntu 22.04+
- RAM : 2 Go minimum
- Disque : 20 Go minimum
- Docker + Docker Compose installés
- rsyslog installé (`sudo apt install -y rsyslog`)
- `node_exporter` installé (`sudo apt install -y prometheus-node-exporter`)

### VMs à superviser
- `node_exporter` installé et accessible sur le port `9100`
- Syslog configuré pour envoyer vers la VM monitoring sur le port `514` UDP

---

## Installation rapide

### 1. Cloner le dépôt

```bash
git clone https://github.com/AmonKm/Stack-monitoring.git
cd Stack-monitoring
```

### 2. Configurer les variables

```bash
cp .env.example .env
nano .env
```

| Variable | Description | Défaut |
|----------|-------------|--------|
| `GF_ADMIN_USER` | Login Grafana | `admin` |
| `GF_ADMIN_PASSWORD` | Mot de passe Grafana | `changeme` |
| `PROMETHEUS_RETENTION` | Durée rétention métriques | `30d` |

### 3. Configurer rsyslog

```bash
sudo mkdir -p /var/log/syslog-remote
sudo chmod 755 /var/log/syslog-remote
sudo cp docs/rsyslog.conf /etc/rsyslog.d/00-promtail-relay.conf
sudo systemctl restart rsyslog
sudo systemctl enable rsyslog
```

Vérifier que rsyslog tourne sans erreur :

```bash
sudo journalctl -u rsyslog --since "1 minute ago" | tail -5
```

### 4. Adapter les targets Prometheus

Éditer `prometheus/targets/si.yml` avec les IPs de vos VMs :

```yaml
- targets:
    - "10.0.0.10:9100"   # ← remplacer par l'IP réelle
  labels:
    env: "si-principal"
    role: "dns"           # ← rôle de la VM

- targets:
    - "10.0.0.11:9100"
  labels:
    env: "si-principal"
    role: "dhcp"

- targets:
    - "10.0.0.20:9100"
  labels:
    env: "si-principal"
    role: "web"

- targets:
    - "10.0.0.21:9100"
  labels:
    env: "si-principal"
    role: "mail"
```

Éditer `prometheus/targets/firewall.yml` :

```yaml
- targets:
    - "10.0.0.254:9100"   # ← IP de votre firewall
  labels:
    env: "si-principal"
    role: "firewall"
    type: "pfsense"
```

Éditer `prometheus/prometheus.yml` — remplacer l'IP de la VM monitoring :

```yaml
- job_name: "monitoring"
  static_configs:
    - targets: ["10.0.0.13:9100"]   # ← IP de votre VM monitoring
      labels:
        role: "monitoring"
```

### 5. Adapter Promtail

Éditer `promtail/promtail-config.yml` — adapter les `__path__` selon les hostnames réels de votre infra.

> **Comment trouver les bons hostnames ?**
> Après avoir démarré rsyslog et configuré les VMs pour envoyer leurs logs :
> ```bash
> ls /var/log/syslog-remote/
> ```
> Les dossiers créés correspondent aux hostnames réels. Utiliser ces valeurs dans la config Promtail.

Exemple :

```yaml
- job_name: "pfsense-firewall"
  static_configs:
    - targets: ["localhost"]
      labels:
        job: "pfsense"
        host: "pfsense"
        type: "firewall"
        __path__: /var/log/syslog-remote/pfSense.home.arpa/filterlog.log
        #                                ^^^^^^^^^^^^^^^^^^
        #                    remplacer par le hostname réel de votre pfsense
```

### 6. Lancer le stack

```bash
docker compose up -d
docker compose ps
```

Accéder à Grafana : `http://<IP_VM_MONITORING>:3000`

---

## Intégration pfsense

Dans l'interface web pfsense :
**Status → System Logs → Settings**

| Paramètre | Valeur |
|-----------|--------|
| Enable Remote Logging | ✅ coché |
| Remote log servers | `<IP_VM_MONITORING>:514` |
| Remote Syslog Contents | ✅ Firewall Events + System Events |
| Log message format | syslog (RFC 5424) |

> **Important** : pour que les logs firewall (`filterlog`) apparaissent, au moins une règle firewall doit avoir l'option **Log** activée dans **Firewall → Rules**.

---

## Intégration VMs Linux

Sur chaque VM à superviser :

**1. Installer node_exporter :**

```bash
sudo apt install -y prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
# Vérifier
curl http://localhost:9100/metrics | head -3
```

**2. Configurer l'envoi syslog :**

Créer `/etc/rsyslog.d/forward.conf` :

```
*.* @<IP_VM_MONITORING>:514
```

```bash
sudo systemctl restart rsyslog
```

**3. Vérifier sur la VM monitoring :**

```bash
ls /var/log/syslog-remote/
# Le hostname de la VM doit apparaître comme dossier
```

---

## Dashboards disponibles

| Dashboard | Source | Contenu |
|-----------|--------|---------|
| **pfsense Firewall** | Loki | Trafic bloqué/autorisé, top IPs, top ports |
| **DHCP & Mail** | Loki | Baux DHCP, machines actives, logs mail |
| **Système** | Prometheus | CPU, RAM, disque, réseau, uptime par VM |
| **Cybersécurité** | Loki | Ports suspects, DNS, machines réseau |

Les dashboards sont chargés automatiquement au démarrage de Grafana depuis `grafana/dashboards/`.

---

## Variables à adapter selon l'infra

| Fichier | Ce qu'il faut changer |
|---------|----------------------|
| `.env` | `GF_ADMIN_PASSWORD`, `PROMETHEUS_RETENTION` |
| `prometheus/targets/si.yml` | IPs et rôles des VMs |
| `prometheus/targets/firewall.yml` | IP du firewall |
| `prometheus/prometheus.yml` | IP de la VM monitoring |
| `promtail/promtail-config.yml` | Hostnames des dossiers dans `/var/log/syslog-remote/` |
| `docs/rsyslog.conf` | Hostname du pfsense si différent de `pfSense.home.arpa` |

---

## Structure du dépôt
```
Stack-monitoring/
├── docker-compose.yml              # Stack principal — 4 services : Prometheus, Loki, Promtail, Grafana
├── setup.sh                        # Script interactif de configuration automatique
├── .env.example                    # Variables d'environnement → copier en .env
├── prometheus/
│   ├── prometheus.yml              # Config Prometheus (scrape interval, règles)
│   ├── targets/
│   │   ├── si.yml                  # IPs et rôles des VMs à superviser
│   │   └── firewall.yml            # IP du firewall pfsense
│   └── rules/                      # Règles d'alerting Prometheus (optionnel)
│   │   ├── alerting.yml            # Surveille et notifie en fonction des règles$
│   │   └── recording.yml           # Optimise les performances des dashboards Grafana
├── loki/
│   └── loki-config.yml             # Config Loki — stockage filesystem, rétention 30j
├── promtail/
│   └── promtail-config.yml         # Sources de logs — pfsense, DHCP, DNS, mail, web
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/            # Déclaration automatique Prometheus + Loki
│   │   └── dashboards/             # Chargement automatique des dashboards au démarrage
│   └── dashboards/                 # Dashboards JSON prêts à l'emploi
│       ├── pfsense-firewall.json   # Trafic firewall, top IPs, ports suspects
│       ├── dhcp-mail.json          # Baux DHCP, machines actives, logs mail
│       ├── systeme.json            # CPU, RAM, disque, réseau, uptime par VM
│       └── cyber.json              # Cybersécurité — ports suspects, DNS, réseau
├── ansible/
│   ├── README.md                   # Instructions d'intégration dans un repo Ansible existant
│   └── tasks/
│       └── monitoring-client.yml   # Tâche Ansible — installe node_exporter + rsyslog sur une VM
└── docs/
    └── rsyslog.conf                # Config rsyslog à copier sur la VM monitoring
```

---

## Dépannage

**Grafana inaccessible**

```bash
docker compose ps
docker logs grafana --tail=20
```

**Pas de métriques dans Prometheus**

```bash
# Vérifier que node_exporter répond sur la VM cible
curl http://<IP_VM>:9100/metrics | head -3
# Vérifier l'état des targets Prometheus
curl http://localhost:9090/api/v1/targets | python3 -m json.tool | grep health
```

**Pas de logs dans Loki**

```bash
# Vérifier que les paquets arrivent sur le port 514
sudo tcpdump -i any udp port 514 -n -c 10
# Vérifier les dossiers créés par rsyslog
ls /var/log/syslog-remote/
# Vérifier les labels disponibles dans Loki
curl http://localhost:3100/loki/api/v1/labels | python3 -m json.tool
```

**Logs pfsense présents mais filterlog vide**
→ Dans pfsense, vérifier que "Firewall Events" est coché dans **Status → System Logs → Settings** et qu'au moins une règle firewall a l'option **Log** activée.

**Loki erreur `empty ring` au démarrage**
→ Normal pendant ~30 secondes au démarrage, disparaît tout seul.

**Dossiers `/var/log/syslog-remote/` vides**
→ Vérifier que le port 514 UDP est libre :

```bash
sudo ss -ulnp | grep 514
```

→ Vérifier rsyslog :

```bash
sudo systemctl status rsyslog
sudo journalctl -u rsyslog --since "5 minutes ago"
```

---

## Auteurs

Groupe 6.2 — Projet supervision infrastructure  
Stack compatible avec toute infrastructure Linux disposant de `node_exporter` et `rsyslog`.

Projet réalisé de manière autonome. Claude (Anthropic) utilisé comme support technique ponctuel pour la vérification de configurations et l'explication de certains fonctionnements.
