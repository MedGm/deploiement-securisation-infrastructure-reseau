# Script de démonstration vidéo — Mini-projet 2

## Objectif
Montrer, en une séquence courte et crédible, les 4 points demandés :
- connexion SSH sécurisée avec MFA
- pare-feu actif
- fail2ban opérationnel
- accès VPN inter-sites

## Topologie à montrer à l’écran
- Siège : pfSense-Siege
- VLAN 10 : serveurs internes
- VLAN 30 : administration
- DMZ : Web-Apache et Mail-Server
- Agence : pfSense-Agence + postes agence

## Rôle réel des machines dans ta topologie
- VPCS uniquement : Admin-PC, Employe-1, Employe-2, Employe-3, Agence-PC-1, Agence-PC-2, AP-WiFi, Switch-Mgmt
- Machines Linux/Docker : AD-LDAP, Fichiers, BDD-MariaDB, Web-Apache, Mail-Server, Internet-NAT, NAT-VLAN10
- Donc : les VPCS servent pour `ping`, `trace`, `nmap` simple et tests réseau de base, mais pas pour `ssh`
- Pour la preuve SSH, utilise `Admin-Linux` une fois ajouté dans VLAN 30, ou un vrai client Linux externe si tu préfères

## Consoles GNS3 à utiliser
- `AD-LDAP` -> `telnet localhost:5044`
- `Admin-PC` -> `telnet localhost:5054`
- `Admin-Linux` -> `telnet localhost:5014`
- `Employe-1` -> `telnet localhost:5048`
- `Employe-2` -> `telnet localhost:5050`
- `Employe-3` -> `telnet localhost:5052`
- `Fichiers` -> `telnet localhost:5046`
- `BDD-MariaDB` -> `telnet localhost:5068`
- `Agence-PC-1` -> `telnet localhost:5056`
- `Agence-PC-2` -> `telnet localhost:5058`
- `Switch-Mgmt` -> `telnet localhost:5064`
- `Mail-Server` -> `telnet localhost:5072`
- `Web-Apache` -> `telnet localhost:5070`

## Préparation avant l’enregistrement
- Démarrer les 2 pfSense et les serveurs Linux utiles
- Vérifier que le tunnel IPSec est établi
- Avoir un vrai client Linux pour lancer la connexion SSH, car `Admin-PC` dans GNS3 est un VPCS et ne dispose pas de client `ssh`
- Ouvrir un terminal sur le serveur cible et un terminal sur la machine d’attaque simulée

## Identifiants de démo
- Connexion console locale sur les serveurs Debian : `root`
- Mot de passe console de base prévu par les scripts cloud-init et hardening : `Mobitech2024!`
- Compte SSH/MFA prévu pour l’administration : `adminit`
- Mot de passe LDAP/local utilisé dans les scripts : `Mobitech2024!`
- Pré-requis SSH pour que la démo passe : la clé publique de l’admin doit être présente dans `/home/adminit/.ssh/authorized_keys`

## Machine à utiliser pour la preuve SSH
- `Admin-PC` du schéma est seulement un VPCS : il sert aux tests `ping`, `trace` et de connectivité basique, pas à `ssh`
- Pour la démonstration SSH, utiliser `Admin-Linux` dans le VLAN 30, ou à défaut le terminal de ta machine Linux hôte si elle est routée vers le lab
- `Admin-Linux` est la machine recommandée pour la démo, car elle remplace le VPCS `Admin-PC` pour les tests SSH
- Console GNS3 du client Linux : `telnet localhost:5014`

## Remarque sur les logs UFW
- Les messages `UFW BLOCK` visibles sur `srv-ldap` pendant la démo viennent du trafic syslog envoyé depuis `192.168.10.20` vers `192.168.10.10:514/UDP`
- Cela ne bloque pas la connexion console ; c’est simplement le pare-feu qui filtre un flux de journalisation non autorisé ou non ouvert

## Déroulé conseillé de la vidéo

### 1. Introduction rapide
Phrase à dire :
"Voici la topologie du mini-projet 2 : un siège avec pfSense, des VLANs segmentés, une DMZ, et un site agence relié par VPN IPSec."

Écran à montrer :
- Vue GNS3 complète
- pfSense-Siege, pfSense-Agence, VLAN 10, VLAN 30, DMZ

### 2. SSH sécurisé avec MFA
Cible recommandée : AD-LDAP ou un serveur durci du siège.

Commande à exécuter depuis un vrai client Linux autorisé :
```bash
ssh -p 2222 adminit@192.168.10.10
```

Machine cliente correcte pour cette preuve : `Admin-Linux` dans VLAN 30. `Admin-PC` reste réservé aux tests VPCS.

Si tu es déjà sur la console locale du serveur, connecte-toi d’abord en `root` avec `Mobitech2024!`, puis vérifie ensuite la session SSH depuis le poste admin.

Si tu obtiens `Permission denied (publickey)`, cela veut dire que la clé n’est pas encore installée. Corrige avant l’enregistrement avec l’une de ces méthodes :
```bash
# depuis le poste admin, générer une clé dédiée si besoin
ssh-keygen -t ed25519 -f ~/.ssh/mp2_adminit -C adminit@mobitech

# puis copier la clé publique vers le serveur cible
ssh-copy-id -i ~/.ssh/mp2_adminit.pub -p 2222 adminit@192.168.10.10
```

Si tu fais la correction directement sur le serveur en console root :
```bash
install -d -m 700 /home/adminit/.ssh
cat /root/.ssh/id_rsa.pub >> /home/adminit/.ssh/authorized_keys
chown -R adminit:adminit /home/adminit/.ssh
chmod 600 /home/adminit/.ssh/authorized_keys
```

Ce qu’il faut montrer :
- la connexion passe sur le port 2222
- la clé SSH est acceptée
- la demande MFA TOTP apparaît
- après saisie du code, l’accès shell est obtenu

Phrase à dire :
"L’accès SSH est limité au VLAN 30 et protégé par authentification par clé plus MFA TOTP."

### 3. Pare-feu actif
Depuis un poste non autorisé, par exemple un poste employé ou agence, lancer un test de blocage.

Exemple de test :
```bash
nmap -Pn -p 22,2222,80,443 192.168.10.10
```

Ou, pour un test plus direct :
```bash
nc -vz 192.168.10.10 2222
```

Ce qu’il faut montrer :
- les ports non autorisés sont filtrés
- dans pfSense, les règles WAN/LAN sont en deny-by-default
- UFW est actif sur le serveur cible

Commande utile sur le serveur pour prouver l’état du pare-feu :
```bash
sudo ufw status verbose
```

Phrase à dire :
"Le filtrage est appliqué à la fois par pfSense et par UFW sur les serveurs."

### 4. fail2ban opérationnel
Depuis une machine de test, provoquer plusieurs échecs d’authentification SSH.

Principe :
- faire 5 tentatives de connexion incorrectes
- puis afficher l’état de fail2ban sur le serveur

Commande de vérification sur le serveur :
```bash
sudo fail2ban-client status sshd
```

Si le serveur web ou mail est utilisé pour la démo, montrer aussi le jail correspondant :
```bash
sudo fail2ban-client status
```

Ce qu’il faut montrer :
- le jail sshd est actif
- l’IP de la machine de test est bannie
- les logs confirment l’action

Phrase à dire :
"Après plusieurs échecs, fail2ban bloque automatiquement l’attaquant pendant 24 heures."

### 5. VPN inter-sites
Depuis un poste de l’agence, montrer l’accès à une ressource du siège.

Exemple de test :
```bash
ping 192.168.10.10
```

ou vers un serveur DMZ si la politique le permet :
```bash
ping 192.168.50.10
```

Puis afficher le statut IPSec dans pfSense :
- phase 1 établie
- phase 2 établie
- tunnel actif entre siège et agence

Phrase à dire :
"Le site agence accède aux ressources du siège uniquement via le tunnel IPSec IKEv2."

## Ordre de montage recommandé
1. Vue globale de la topologie
2. Connexion SSH avec MFA
3. Blocage pare-feu
4. Ban fail2ban après tentatives ratées
5. Ping inter-sites et état IPSec établi

## Version ultra-courte pour voix off
"Cette infrastructure est segmentée par VLANs, protégée par pfSense et durcie sur chaque serveur. L’accès d’administration se fait en SSH sur le port 2222 avec MFA TOTP. Les tentatives non autorisées sont bloquées par le pare-feu et par fail2ban. Enfin, les deux sites communiquent via un tunnel VPN IPSec IKEv2 chiffré."

## Remarque pratique
Si tu n’as pas de vrai poste Linux dans le VLAN 30, fais la démonstration SSH depuis une VM de test ou depuis la machine de contrôle reliée au réseau d’administration, mais garde bien le contexte visuel du VLAN 30 à l’écran.