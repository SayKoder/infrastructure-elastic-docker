\# Infrastructure Distribuée - Architecture 3 VM Conteneurisées



> Projet réalisé dans le cadre d'un TP Docker Avancé Bac+4

> Auteur : SayKoder  

> Dépôt : https://github.com/SayKoder/infrastructure-elastic-docker



---



\## Table des matières



1\. \[Vue d'ensemble](#vue-densemble)

2\. \[Prérequis](#prérequis)

3\. \[Architecture réseau](#architecture-réseau)

4\. \[Déploiement from scratch](#déploiement-from-scratch)

5\. \[Structure du dépôt](#structure-du-dépôt)

6\. \[VM1 — Stack Applicative](#vm1--stack-applicative)

7\. \[VM2 — Stack Logging](#vm2--stack-logging)

8\. \[VM3 — Stack Monitoring](#vm3--stack-monitoring)

9\. \[Sécurité](#sécurité)

10\. \[Accès aux services](#accès-aux-services)

11\. \[Commandes utiles](#commandes-utiles)



---



\## Vue d'ensemble



Ce projet déploie une architecture distribuée de services conteneurisés sur \*\*3 machines virtuelles avec Rocky (V10) Linux\*\*, exposées en \*\*HTTPS\*\* via \*\*Traefik\*\* avec une \*\*autorité de certification (CA) personnelle\*\*.



```

┌─────────────────────────────────────────────────────────────┐

│                    Poste Windows (Host)                      │

│             Navigateur → https://\*.local                     │

└──────────────┬───────────────┬───────────────┬──────────────┘

&nbsp;              │               │               │

&nbsp;       XXX.XXX.XX.103   XXX.XXX.XX.101   XXX.XXX.XX.102

&nbsp;              │               │               │

&nbsp;       ┌──────▼──────┐  ┌─────▼──────┐  ┌────▼────────┐

&nbsp;       │    VM1      │  │    VM2     │  │    VM3      │

&nbsp;       │    Apps     │  │  Logging   │  │ Monitoring  │

&nbsp;       │─────────────│  │────────────│  │─────────────│

&nbsp;       │  Traefik    │  │  Traefik   │  │  Traefik    │

&nbsp;       │  WordPress  │  │  Elastic   │  │  Uptime     │

&nbsp;       │  MariaDB x2 │  │  Logstash  │  │  Kuma       │

&nbsp;       │  Keycloak   │  │  Kibana    │  └─────────────┘

&nbsp;       │  phpMyAdmin │  └────────────┘

&nbsp;       │  Filebeat   │       

&nbsp;       └─────────────┘   

&nbsp;             │ logs via Filebeat

&nbsp;             └──────────────────→ VM2:5044


```



\## Prérequis



\### Logiciels à installer sur le poste Windows (Si besoins)



\- \*\*VirtualBox\*\* — https://www.virtualbox.org



\### Configuration des VM



Chaque VM est sous \*\*Rocky Linux 10 minimale\*\* avec :



| VM | Rôle | IP Host-Only | RAM | Disque |

|---|---|---|---|---|

| VM1 | Apps | 192.168.56.103 | 3.5 Go | 40 Go |

| VM2 | Logging | 192.168.56.101 | 3.5 Go | 40 Go |

| VM3 | Monitoring | 192.168.56.102 | 2 Go | 20 Go |



Chaque VM possède \*\*deux cartes réseau VirtualBox\*\* :

\- \*\*Carte 1 — NAT\*\* : accès internet

\- \*\*Carte 2 — Host-Only\*\* : réseau privé `XXX.XXX.XX.X`



\### Installation de base sur chaque VM



```bash

dnf update -y

dnf install -y git openssh-server

dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker sshd

usermod -aG docker $USER

```



\### Fix obligatoire — compatibilité Docker / Traefik



Rocky Linux 10 + Docker 29 nécessite ce correctif sur \*\*chaque VM\*\* sinon Traefik crash :



```bash

cat > /etc/docker/daemon.json << EOF

{

&nbsp; "min-api-version": "1.24"

}

EOF

systemctl restart docker

```



\### IP persistantes via NetworkManager



Les IPs doivent être configurées via `nmcli` pour survivre aux redémarrages :



```bash

\# Sur VM1 (par exemple)

nmcli con add type ethernet ifname enp0s8 con-name host-only ip4 192.168.56.103/24

nmcli con up host-only



\# Sur VM2 (par exemple)

nmcli con add type ethernet ifname enp0s8 con-name host-only ip4 192.168.56.101/24

nmcli con up host-only



\# Sur VM3 (par exemple)

nmcli con add type ethernet ifname enp0s8 con-name host-only ip4 192.168.56.102/24

nmcli con up host-only

```



\### Fichier hosts Windows



Dans `C:\\Windows\\System32\\drivers\\etc\\hosts` (Besoin pour que le pc reconnaise les liens en local | En admin avec la note):



```

192.168.56.103   wordpress.local keycloak.local phpmyadmin.local traefik.apps.local

192.168.56.101   kibana.local logging.local traefik.logging.local

192.168.56.102   monitoring.local uptime.local traefik.monitoring.local

```



---



\## Architecture réseau



\### Réseau Docker par VM



Chaque VM utilise un réseau Docker externe partagé `traefik-net` entre Traefik et les services, plus des réseaux internes pour isoler les bases de données :



| VM | Réseau externe | Réseaux internes |

|---|---|---|

| VM1 | `traefik-net` | `wordpress-net`, `keycloak-net` |

| VM2 | `traefik-net` | `elk-net` |

| VM3 | `traefik-net` | `kuma-net` |



---



\## Déploiement from scratch



\### Étape 1 - Cloner le repo sur VM1



```bash

git clone https://github.com/SayKoder/infrastructure-elastic-docker.git
```



\### Étape 2 - Créer les .env depuis les templates



Sur chaque VM, copie les `.env.example` et remplis les vrais mots de passe :



```bash

\# VM1

cp vm1/traefik/.env.example vm1/traefik/.env

cp vm1/wordpress/.env.example vm1/wordpress/.env

cp vm1/keycloak/.env.example vm1/keycloak/.env

cp vm1/filebeat/.env.example vm1/filebeat/.env



\# VM2

cp vm2/traefik/.env.example vm2/traefik/.env

cp vm2/elk/.env.example vm2/elk/.env



\# VM3

cp vm3/traefik/.env.example vm3/traefik/.env

cp vm3/kuma/.env.example vm3/kuma/.env

```



\### Étape 3 - Générer et distribuer les certificats



Depuis VM1 (SSH doit être configuré entre VM1 → VM2 et VM1 → VM3) :



```bash

bash ~/projet/scripts/generate-certs.sh

```



Ce script génère la CA racine, les certificats pour chaque VM, les installe sur VM1 et les distribue automatiquement sur VM2 et VM3 via SCP.



\*\*Sur Windows\*\* - importer la CA manuellement :



```powershell

\# Copie rootCA.pem depuis VM1 vers Windows puis dans PowerShell admin :

Import-Certificate -FilePath "rootCA.crt" -CertStoreLocation Cert:\\LocalMachine\\Root

```



(Pour Firefox : Paramètres -> Confidentialité -> Certificats -> Autorités -> Importer)



\### Étape 4 - Lancer VM1



```bash

bash ~/projet/scripts/setup-vm1.sh

```



\### Étape 5 - Cloner et lancer VM2



```bash

\# Sur VM2

git clone https://github.com/SayKoder/infrastructure-elastic-docker.git

\# Crée les .env (voir étape 2)

bash ~/projet/scripts/setup-vm2.sh

```



\### Étape 6 - Cloner et lancer VM3



```bash

\# Sur VM3

git clone https://github.com/SayKoder/infrastructure-elastic-docker.git

\# Crée les .env (voir étape 2)

bash ~/projet/scripts/setup-vm3.sh

```



\### Étape 7 - Configurer Keycloak



Dans l'Administration Console (`https://keycloak.local`) :



1\. Crée un Realm `monlabo`

2\. Crée un Client `wordpress` avec OpenID Connect

3\. Configure les redirect URIs : `https://wordpress.local/\*`

4\. Crée un utilisateur de test

5\. Dans WordPress -> Réglages -> OpenID Connect, renseigne le Client ID et Secret



---



\## Structure du dépôt



```

infrastructure-elastic-docker/

├── .gitignore

├── README.md

├── scripts/

│   ├── generate-certs.sh      # Génère et distribue la CA et les certificats

│   ├── setup-vm1.sh           # Configure et lance la stack VM1

│   ├── setup-vm2.sh           # Configure et lance la stack VM2

│   └── setup-vm3.sh           # Configure et lance la stack VM3

├── vm1/

│   ├── traefik/

│   │   ├── docker-compose.yml

│   │   ├── traefik.yml

│   │   ├── tls.yml

│   │   └── .env.example

│   ├── wordpress/

│   │   ├── docker-compose.yml

│   │   ├── wordpress-entrypoint.sh

│   │   └── .env.example

│   ├── keycloak/

│   │   ├── docker-compose.yml

│   │   └── .env.example

│   └── filebeat/

│       ├── docker-compose.yml

│       ├── filebeat.yml

│       └── .env.example

├── vm2/

│   ├── traefik/

│   │   ├── docker-compose.yml

│   │   ├── traefik.yml

│   │   ├── tls.yml

│   │   └── .env.example

│   └── elk/

│       ├── docker-compose.yml

│       ├── pipeline/

│       │   └── logstash.conf

│       └── .env.example

└── vm3/

&nbsp;   ├── traefik/

&nbsp;   │   ├── docker-compose.yml

&nbsp;   │   ├── traefik.yml

&nbsp;   │   ├── tls.yml

&nbsp;   │   └── .env.example

&nbsp;   └── kuma/

&nbsp;       ├── docker-compose.yml

&nbsp;       ├── Dockerfile

&nbsp;       └── .env.example

```



---



\## VM1 - Stack Applicative



\### Ordre de démarrage



```bash

docker network create traefik-net

cd vm1/traefik   \&\& docker compose up -d

cd vm1/keycloak  \&\& docker compose up -d   # Attendre ~4 min

cd vm1/wordpress \&\& docker compose up -d

cd vm1/filebeat  \&\& docker compose up -d

```



\### CA dans WordPress



WordPress doit faire confiance à la CA pour communiquer avec Keycloak en HTTPS. Le script `wordpress-entrypoint.sh` installe automatiquement la CA au démarrage du container :



```bash

\#!/bin/bash

update-ca-certificates

exec docker-entrypoint.sh apache2-foreground

```



\### OpenID Connect — Flux d'authentification



```

Utilisateur → https://wordpress.local/wp-login.php

&nbsp;    | clique "Login with OpenID Connect"

Redirigé → https://keycloak.local/realms/monlabo/...

&nbsp;    | saisit ses credentials Keycloak

Token JWT retourné → WordPress valide via JWKS

&nbsp;    |

Utilisateur connecté sur WordPress

```



---



\## VM2 - Stack Logging



\### Prérequis kernel



Elasticsearch nécessite ce paramètre :



```bash

sysctl -w vm.max\_map\_count=262144

echo "vm.max\_map\_count=262144" >> /etc/sysctl.conf

```



\### Ordre de démarrage



```bash

docker network create traefik-net

cd vm2/traefik \&\& docker compose up -d

cd vm2/elk     \&\& docker compose up -d



\# Après 60s - configure kibana\_system

sleep 60

curl -s -X POST "http://localhost:9200/\_security/user/kibana\_system/\_password" \\

&nbsp; -u elastic:VOTRE\_MOT\_DE\_PASSE \\

&nbsp; -H "Content-Type: application/json" \\

&nbsp; -d '{"password":"MOT\_DE\_PASSE\_KIBANA"}'



docker compose restart kibana

```

\### Data View Kibana



Kibana → Stack Management → Data Views → Create :



```

Name          : Logs Docker

Index pattern : logs-\*

Timestamp     : @timestamp

```



---



\## VM3 — Stack Monitoring



\### Image custom Uptime Kuma



Uptime Kuma utilise Node.js qui a son propre store de certificats - il ne reconnaît pas nativement notre CA. Un `Dockerfile` custom intègre la CA dans l'image :



```dockerfile

FROM louislam/uptime-kuma:1

COPY monlabo-ca.crt /usr/local/share/ca-certificates/monlabo-ca.crt

RUN update-ca-certificates

ENV NODE\_EXTRA\_CA\_CERTS=/usr/local/share/ca-certificates/monlabo-ca.crt

```



\### Ordre de démarrage



```bash

docker network create traefik-net

cd vm3/traefik \&\& docker compose up -d

cd vm3/kuma    \&\& docker compose build \&\& docker compose up -d

```



\### Monitors configurés



| Service | URL surveillée |

|---|---|

| WordPress | https://wordpress.local |

| phpMyAdmin | https://phpmyadmin.local |

| Keycloak | https://keycloak.local |

| Traefik Apps | https://traefik.apps.local |

| Kibana | https://kibana.local |

| Traefik Logging | https://traefik.logging.local |

| Traefik Monitoring | https://traefik.monitoring.local |



---



\## Sécurité



```bash

\# Génération du hash (les $ doivent être doublés en $$ dans docker-compose.yml)

htpasswd -nb admin VotreMotDePasse

```



\### Secrets dans les .env



Aucun secret n'est committé sur Git. Les `.env` sont dans le `.gitignore`. Seuls les `.env.example` avec des valeurs `changeme` sont versionnés.



---



\## Commandes utiles



\### Vérifier l'état des services



```bash

\# Depuis n'importe quel dossier de stack

docker compose ps

docker compose logs -f \[nom\_service]

```



\### Redémarrer un service



```bash

docker compose restart \[nom\_service]

```



\### Vérifier la connectivité entre VM



```bash

\# Depuis VM1 — teste Logstash sur VM2

curl -v telnet://192.168.56.101:5044



\# Depuis VM3 — teste WordPress sur VM1

docker exec uptime-kuma curl -sk https://wordpress.local -o /dev/null -w "%{http\_code}"

```



\### Vérifier les index Elasticsearch



```bash

curl -s http://localhost:9200/\_cat/indices?v -u elastic:VOTRE\_MOT\_DE\_PASSE

```



\### Vérifier les IPs des VM après redémarrage



```bash

ip a | grep 192.168

\# Si l'IP a disparu :

nmcli con up host-only

```



\### Mettre à jour depuis GitHub



```bash

cd ~/projet

git pull

\# Relancer les services modifiés

cd vm1/traefik \&\& docker compose down \&\& docker compose up -d

```

