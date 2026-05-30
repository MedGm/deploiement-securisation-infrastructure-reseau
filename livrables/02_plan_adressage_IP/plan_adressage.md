# Plan d'adressage IP — Infrastructure Mobitech

| Réseau / VLAN       | Adresse réseau    | Masque          | Passerelle      | Plage DHCP            | Usage                        |
|---------------------|-------------------|-----------------|-----------------|----------------------|------------------------------|
| WAN (pfSense)       | DHCP ISP          | —               | ISP             | —                    | Accès Internet               |
| VLAN 10 — Serveurs  | 192.168.10.0/24   | 255.255.255.0   | 192.168.10.1    | statique             | Serveurs internes (AD, Web…) |
| VLAN 20 — Postes    | 192.168.20.0/24   | 255.255.255.0   | 192.168.20.1    | .100 – .200          | Postes employés              |
| VLAN 30 — DMZ       | 192.168.30.0/24   | 255.255.255.0   | 192.168.30.1    | statique             | Services exposés (HTTP/S)    |
| VPN IPSec (site B)  | 10.10.10.0/30     | 255.255.255.252 | —               | —                    | Tunnel site-à-site           |
| LAN Agence distante | 192.168.100.0/24  | 255.255.255.0   | 192.168.100.1   | .50 – .150           | Postes agence                |

## Hôtes statiques notables

| Hôte              | IP               | Rôle                        |
|-------------------|------------------|-----------------------------|
| pfSense (LAN)     | 192.168.10.1     | Pare-feu / routeur principal|
| AD-LDAP Server    | 192.168.10.10    | OpenLDAP + rsyslog          |
| Web Server (DMZ)  | 192.168.30.10    | Apache HTTPS                |
| pfSense agence    | 192.168.100.1    | Routeur agence + VPN        |

> Voir aussi le rapport technique (rapport_mp2.pdf) section 2 pour le schéma complet.
