#!/bin/bash
# ============================================================
# generate-certs.sh
# Génère la CA, les certificats pour les 3 VM et les distribue
# À exécuter sur VM1 en root
# ============================================================
set -e

# ── Variables — adapter si besoin ────────────────────────────
VM1_IP="192.168.56.103"
VM2_IP="192.168.56.101"
VM3_IP="192.168.56.102"
VM2_USER="root"
VM3_USER="root"

echo "=== Génération de la CA et des certificats ==="

mkdir -p ~/ca && cd ~/ca

# ── CA racine ────────────────────────────────────────────────
echo "[1/7] Génération de la CA racine..."
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key \
  -sha256 -days 3650 -out rootCA.pem \
  -subj "/C=FR/ST=IDF/L=Paris/O=MonLabo/CN=MonLabo-RootCA"

# ── Certificat VM1 ───────────────────────────────────────────
echo "[2/7] Certificat VM1..."
cat > vm1.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = wordpress.local
DNS.2 = keycloak.local
DNS.3 = phpmyadmin.local
DNS.4 = traefik.apps.local
IP.1 = $VM1_IP
EOF

openssl genrsa -out vm1.key 2048
openssl req -new -key vm1.key -out vm1.csr \
  -subj "/C=FR/ST=IDF/L=Paris/O=MonLabo/CN=vm1.apps.local"
openssl x509 -req -in vm1.csr -CA rootCA.pem -CAkey rootCA.key \
  -CAcreateserial -out vm1.crt -days 825 -sha256 -extfile vm1.ext

# ── Certificat VM2 ───────────────────────────────────────────
echo "[3/7] Certificat VM2..."
cat > vm2.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = kibana.local
DNS.2 = logging.local
DNS.3 = traefik.logging.local
IP.1 = $VM2_IP
EOF

openssl genrsa -out vm2.key 2048
openssl req -new -key vm2.key -out vm2.csr \
  -subj "/C=FR/ST=IDF/L=Paris/O=MonLabo/CN=vm2.logging.local"
openssl x509 -req -in vm2.csr -CA rootCA.pem -CAkey rootCA.key \
  -CAcreateserial -out vm2.crt -days 825 -sha256 -extfile vm2.ext

# ── Certificat VM3 ───────────────────────────────────────────
echo "[4/7] Certificat VM3..."
cat > vm3.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = monitoring.local
DNS.2 = uptime.local
DNS.3 = traefik.monitoring.local
IP.1 = $VM3_IP
EOF

openssl genrsa -out vm3.key 2048
openssl req -new -key vm3.key -out vm3.csr \
  -subj "/C=FR/ST=IDF/L=Paris/O=MonLabo/CN=vm3.monitoring.local"
openssl x509 -req -in vm3.csr -CA rootCA.pem -CAkey rootCA.key \
  -CAcreateserial -out vm3.crt -days 825 -sha256 -extfile vm3.ext

# ── Installation sur VM1 ─────────────────────────────────────
echo "[5/7] Installation CA et certificats sur VM1..."
cp rootCA.pem /etc/pki/ca-trust/source/anchors/monlabo-ca.pem
update-ca-trust
mkdir -p /opt/certs
cp vm1.crt vm1.key rootCA.pem /opt/certs/
chmod 600 /opt/certs/*.key

# ── Distribution sur VM2 ─────────────────────────────────────
echo "[6/7] Distribution vers VM2 ($VM2_IP)..."
ssh $VM2_USER@$VM2_IP "mkdir -p /opt/certs"
scp rootCA.pem $VM2_USER@$VM2_IP:/etc/pki/ca-trust/source/anchors/monlabo-ca.pem
scp vm2.crt vm2.key rootCA.pem $VM2_USER@$VM2_IP:/opt/certs/
ssh $VM2_USER@$VM2_IP "update-ca-trust && chmod 600 /opt/certs/*.key"

# ── Distribution sur VM3 ─────────────────────────────────────
echo "[7/7] Distribution vers VM3 ($VM3_IP)..."
ssh $VM3_USER@$VM3_IP "mkdir -p /opt/certs"
scp rootCA.pem $VM3_USER@$VM3_IP:/etc/pki/ca-trust/source/anchors/monlabo-ca.pem
scp vm3.crt vm3.key rootCA.pem $VM3_USER@$VM3_IP:/opt/certs/
ssh $VM3_USER@$VM3_IP "update-ca-trust && chmod 600 /opt/certs/*.key"

echo ""
echo "=== Certificats générés et distribués sur VM2 et VM3 ==="
echo ""
echo "Reste à faire manuellement sur Windows :"
echo "  1. Copie ~/ca/rootCA.pem sur ton PC Windows"
echo "  2. Renomme-le rootCA.crt"
echo "  3. Dans PowerShell admin :"
echo "     Import-Certificate -FilePath rootCA.crt -CertStoreLocation Cert:\LocalMachine\Root"
echo "  4. Firefox : Paramètres → Confidentialité → Certificats → Autorités → Importer"