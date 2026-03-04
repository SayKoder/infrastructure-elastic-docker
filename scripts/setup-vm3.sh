#!/bin/bash
# ============================================================
# setup-vm3.sh
# Configure et lance la stack monitoring sur VM3
# À exécuter sur VM3 en root après avoir cloné le repo
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM3_DIR="$REPO_DIR/vm3"

echo "=== Setup VM3 — Stack Monitoring ==="

# ── Prérequis système ────────────────────────────────────────
echo "[1/5] Configuration système..."

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

# ── Vérification des certificats ────────────────────────────
echo "[2/5] Vérification des certificats..."
if [ ! -f /opt/certs/vm3.crt ] || [ ! -f /opt/certs/vm3.key ]; then
  echo "ERREUR : Certificats manquants dans /opt/certs/"
  echo "Lance d'abord generate-certs.sh sur VM1"
  exit 1
fi

# ── Vérification des .env ────────────────────────────────────
echo "[3/5] Vérification des fichiers .env..."
for dir in traefik kuma; do
  if [ ! -f "$VM3_DIR/$dir/.env" ]; then
    echo "ERREUR : $VM3_DIR/$dir/.env manquant !"
    echo "  cp $VM3_DIR/$dir/.env.example $VM3_DIR/$dir/.env"
    exit 1
  fi
done

# ── Copie de la CA pour Uptime Kuma ─────────────────────────
echo "[4/5] Copie de la CA..."
cp /opt/certs/rootCA.pem "$VM3_DIR/kuma/monlabo-ca.crt"

# ── Réseau Docker partagé ────────────────────────────────────
docker network create traefik-net 2>/dev/null || echo "  → traefik-net déjà existant"

# ── Lancement des stacks ─────────────────────────────────────
echo "[5/5] Lancement des services..."

echo "  → Traefik"
cd "$VM3_DIR/traefik" && docker compose up -d

echo "  → Uptime Kuma (build custom avec CA intégrée)"
cd "$VM3_DIR/kuma"
docker compose build --no-cache
docker compose up -d

sleep 10
echo ""
echo "=== VM3 prête ==="
echo ""
echo "Services disponibles :"
echo "  https://uptime.local  (crée ton compte au premier accès)"
echo "  https://traefik.monitoring.local"