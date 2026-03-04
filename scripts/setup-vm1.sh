#!/bin/bash
# ============================================================
# setup-vm1.sh
# Configure et lance la stack applicative sur VM1
# À exécuter sur VM1 en root après avoir cloné le repo
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM1_DIR="$REPO_DIR/vm1"

echo "=== Setup VM1 — Stack Applicative ==="

# ── Prérequis système ────────────────────────────────────────
echo "[1/7] Configuration système..."

# Fix compatibilité Docker / Traefik
cat > /etc/docker/daemon.json << EOF
{
  "min-api-version": "1.24"
}
EOF
systemctl restart docker
sleep 5

# Firewall
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# Dossiers de logs
mkdir -p /var/log/containers/wordpress
mkdir -p /var/log/containers/phpmyadmin
mkdir -p /var/log/containers/keycloak

# ── Vérification des certificats ────────────────────────────
echo "[2/7] Vérification des certificats..."
if [ ! -f /opt/certs/vm1.crt ] || [ ! -f /opt/certs/vm1.key ]; then
  echo "ERREUR : Certificats manquants dans /opt/certs/"
  echo "Lance d'abord : bash scripts/generate-certs.sh"
  exit 1
fi

# ── Vérification des .env ────────────────────────────────────
echo "[3/7] Vérification des fichiers .env..."
for dir in traefik wordpress keycloak filebeat; do
  if [ ! -f "$VM1_DIR/$dir/.env" ]; then
    echo "ERREUR : $VM1_DIR/$dir/.env manquant !"
    echo "Copie le .env.example et remplis les valeurs :"
    echo "  cp $VM1_DIR/$dir/.env.example $VM1_DIR/$dir/.env"
    exit 1
  fi
done

# ── Copie de la CA pour WordPress et Kuma ───────────────────
echo "[4/7] Copie de la CA..."
cp /opt/certs/rootCA.pem "$VM1_DIR/wordpress/monlabo-ca.crt"

# ── Réseau Docker partagé ────────────────────────────────────
echo "[5/7] Création du réseau Docker..."
docker network create traefik-net 2>/dev/null || echo "  → traefik-net déjà existant"

# ── Lancement des stacks dans l'ordre ───────────────────────
echo "[6/7] Lancement des services..."

echo "  → Traefik"
cd "$VM1_DIR/traefik" && docker compose up -d

echo "  → Keycloak (MariaDB + Keycloak)"
cd "$VM1_DIR/keycloak" && docker compose up -d

echo "  → WordPress (MariaDB + WordPress + phpMyAdmin)"
cd "$VM1_DIR/wordpress" && docker compose up -d

echo "  → Filebeat"
cd "$VM1_DIR/filebeat" && docker compose up -d

# ── Vérification finale ──────────────────────────────────────
echo "[7/7] Vérification..."
sleep 15

echo ""
echo "État des services :"
for dir in traefik keycloak wordpress filebeat; do
  echo "── $dir ──"
  cd "$VM1_DIR/$dir" && docker compose ps --format "table {{.Name}}\t{{.Status}}"
done

echo ""
echo "=== VM1 prête ==="
echo ""
echo "Attends ~4 minutes que Keycloak finisse de démarrer."
echo ""
echo "Services disponibles :"
echo "  https://wordpress.local"
echo "  https://phpmyadmin.local"
echo "  https://keycloak.local"
echo "  https://traefik.apps.local"