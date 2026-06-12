# Commandes pour la Démonstration Vidéo (GNS3)

Ce guide résume uniquement les commandes exactes à saisir dans les consoles des différents nœuds GNS3 pour enregistrer la démonstration des parties **SSH MFA**, **Pare-feu (UFW)** et **Fail2ban**.

---

## 1. Console : Admin-Linux

### Étape A : Connexion SSH standard (MFA)
Pour faire la démonstration de la connexion à double facteur (Clé publique + Code TOTP Google Authenticator) :
```bash
ssh -p 2222 adminit@192.168.10.10
```
* **Attendu :** 
  1. La clé SSH est acceptée automatiquement (pas de mot de passe requis pour la clé).
  2. L'invite de code apparaît : `(adminit@192.168.10.10) Verification code:`
  3. Saisissez votre code TOTP actuel depuis votre application de double facteur (ou un code de secours valide comme `39101900`).

---

## 2. Console : srv-ldap (LDAP Server)

### Étape B : Vérification du Pare-feu (UFW)
Affichez le statut et les règles actives du pare-feu pour prouver la restriction d'administration :
```bash
ufw status verbose
```
* **Attendu :** Le statut est `active`, et l'accès au port `2222/tcp` est limité à `192.168.30.0/24` (le VLAN Admin).

### Étape C : Vérification de la protection brute-force (Fail2ban)
Affichez le statut de la prison SSH pour prouver que le service surveille activement le port 2222 :
```bash
fail2ban-client status sshd
```
* **Attendu :** La prison est active avec `0` IP actuellement bannie.

---

## 3. Console : srv-fichiers

### Étape D : Démonstration du blocage du Pare-feu (UFW)
Depuis ce serveur situé dans le VLAN 10 (non autorisé à administrer le LDAP), tentez d'atteindre le port SSH 2222 :
```bash
timeout 3 bash -c '</dev/tcp/192.168.10.10/2222' && echo "Ouvert" || echo "Bloqué par le pare-feu"
```
* **Attendu :** Affiche `Bloqué par le pare-feu` après 3 secondes.

---

## 4. Test Fail2ban (Simulation d'attaque & Ban)

### Étape E : Saisie de codes erronés (Console : Admin-Linux)
Lancez la commande SSH :
```bash
ssh -p 2222 adminit@192.168.10.10
```
1. Lorsque le code de vérification est demandé, saisissez un code faux (ex: `000000`) et appuyez sur Entrée.
2. Répétez cette opération (relancer la commande et saisir un code faux) **5 fois d'affilée**.
3. À la 5ème tentative échouée, le serveur vous bloquera immédiatement.

### Étape F : Vérification du Ban (Console : srv-ldap)
Affichez à nouveau l'état de fail2ban sur le serveur :
```bash
fail2ban-client status sshd
```
* **Attendu :** Le champ `Banned IP list` affiche maintenant l'adresse IP de l'administrateur : `192.168.30.50`.

### Étape G : Unban de secours (Console : srv-ldap)
Pour débannir la machine d'administration après l'enregistrement ou pour continuer vos tests :
```bash
fail2ban-client set sshd unbanip 192.168.30.50
```
