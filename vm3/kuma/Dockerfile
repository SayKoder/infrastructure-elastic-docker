FROM louislam/uptime-kuma:1

# Copie la CA dans l'image
COPY monlabo-ca.crt /usr/local/share/ca-certificates/monlabo-ca.crt

# Installe la CA dans le store système
RUN update-ca-certificates

# Configure Node.js pour utiliser la CA
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/monlabo-ca.crt