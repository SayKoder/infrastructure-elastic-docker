#!/bin/bash
# ============================================================
# setup-vm2.sh
# Configure et lance la stack logging sur VM2
# À exécuter sur VM2 en root après avoir cloné le repo
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM2_DIR="$REPO_DIR/vm2"

echo "=== Setup VM2 — Stack Logging ==="

# ── Prérequis système ────────────────────────────────────────
echo "[1/6] Configuration système..."

# Fix compatibilité Docker / Traefik
cat > /etc/docker/daemon.json << EOF
{
  "min-api-version": "1.24"
}
EOF
systemctl restart docker
sleep 5

# Elasticsearch nécessite ce paramètre kernel
sysctl -w vm.max_map_count=262144
grep -q "vm.max_map_count" /etc/sysctl.conf || \
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Firewall
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=5044/tcp
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# ── Vérification des certificats ────────────────────────────
echo "[2/6] Vérification des certificats..."
if [ ! -f /opt/certs/vm2.crt ] || [ ! -f /opt/certs/vm2.key ]; then
  echo "ERREUR : Certificats manquants dans /opt/certs/"
  echo "Lance d'abord generate-certs.sh sur VM1"
  exit 1
fi

# ── Vérification des .env ────────────────────────────────────
echo "[3/6] Vérification des fichiers .env..."
for dir in traefik elk; do
  if [ ! -f "$VM2_DIR/$dir/.env" ]; then
    echo "ERREUR : $VM2_DIR/$dir/.env manquant !"
    echo "  cp $VM2_DIR/$dir/.env.example $VM2_DIR/$dir/.env"
    exit 1
  fi
done

# ── Réseau Docker partagé ────────────────────────────────────
echo "[4/6] Création du réseau Docker..."
docker network create traefik-net 2>/dev/null || echo "  → traefik-net déjà existant"

# ── Lancement des stacks ─────────────────────────────────────
echo "[5/6] Lancement des services..."

echo "  → Traefik"
cd "$VM2_DIR/traefik" && docker compose up -d

echo "  → ELK Stack (Elasticsearch + Kibana + Logstash)"
cd "$VM2_DIR/elk" && docker compose up -d

# ── Configuration Elasticsearch ──────────────────────────────
echo "[6/6] Configuration Elasticsearch..."
echo "  Attente du démarrage d'Elasticsearch (60s)..."
sleep 60

ELASTIC_PASSWORD=$(grep "^ELASTIC_PASSWORD=" "$VM2_DIR/elk/.env" | cut -d= -f2)
KIBANA_PASSWORD=$(grep "^KIBANA_PASSWORD=" "$VM2_DIR/elk/.env" | cut -d= -f2)

echo "  Configuration du mot de passe kibana_system..."
curl -s -X POST "http://localhost:9200/_security/user/kibana_system/_password" \
  -u elastic:$ELASTIC_PASSWORD \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$KIBANA_PASSWORD\"}" | grep -q "{}" && \
  echo "  → kibana_system configuré" || echo "  → Erreur configuration kibana_system"

echo "  Redémarrage de Kibana..."
cd "$VM2_DIR/elk" && docker compose restart kibana

echo ""
echo "=== VM2 prête ==="
echo ""
echo "Services disponibles :"
echo "  https://kibana.local"
echo "  https://traefik.logging.local"
echo ""
echo "Kibana prend ~2 minutes à démarrer après la configuration."