#!/bin/bash

# Vérifier si .env existe
if [ ! -f .env ]; then
    echo "=============================================="
    echo "  PREMIER DÉMARRAGE"
    echo "  Création du .env depuis .env.example"
    echo "=============================================="
    cp .env.example .env
fi

# Avertissement mots de passe par défaut
if grep -q "admin123\|grafana123\|minioadmin123" .env; then
    echo ""
    echo "  ATTENTION — Mots de passe par défaut détectés"
    echo "  Editez le fichier .env avant de déployer en production !!!"
    echo "  nano .env"
    echo ""
    read -p "  Continuer quand même ? (o/N) " confirm
    if [ "$confirm" != "o" ] && [ "$confirm" != "O" ]; then
        echo "  Déploiement annulé."
        exit 1
    fi
fi

echo "==> Lancement de la stack monitoring..."
docker compose up -d

echo ""
echo "=============================================="
echo "  Stack monitoring opérationnelle"
echo "  Grafana   : http://localhost:3000"
echo "  Prometheus: http://localhost:9090"
echo "  MinIO     : http://localhost:9001"
echo "=============================================="
