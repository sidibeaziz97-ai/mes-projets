#!/bin/bash
#
# setup_kiosk_complete.sh
# ------------------------------------------------------------
# SCRIPT FINAL COMPLET - Poste kiosque Debian 13 (XFCE + LightDM)
# Regroupe TOUT ce qui a ete valide en conditions reelles sur FR-WST177 :
#
#   - Ouverture automatique de Firefox sur l'URL ASWO IPM au demarrage
#   - Relance automatique de Firefox si l'utilisateur le ferme
#   - Extensions / plugins / themes desactives (policies.json)
#   - Ctrl+T redirige vers l'URL fixe (raccourci clavier XFCE, a finir en GUI)
#   - Bouton "+" (nouvel onglet) masque dans la barre d'onglets (userChrome.css, a finir en GUI)
#   - Utilisateur "logistique" : session graphique auto-login, SANS sudo, SANS ssh
#   - Utilisateur "technicien" : sudo active, ssh active (pour intervention)
#   - Connexion SSH root BLOQUEE
#   - Mecanisme de personnalisation du hostname au premier demarrage
#     d'un poste clone (avec le correctif Plymouth/LightDM valide)
#
# PREREQUIS avant de lancer ce script :
#   - Debian 13 avec XFCE + LightDM DEJA installes et fonctionnels
#   - Firefox (paquet officiel Mozilla) DEJA installe, binaire "firefox"
#
# A executer en root, sur le poste "modele" (celui qui sera clone) :
#   sudo bash setup_kiosk_complete.sh
#
# APRES ce script, il reste 2 reglages manuels a faire une seule fois en
# interface graphique (voir le message final), PUIS lancer
# prepare_image_for_cloning.sh juste avant de capturer l'image disque.
# ------------------------------------------------------------

set -euo pipefail

### ==== VARIABLES A ADAPTER SI BESOIN ====
KIOSK_URL="https://ipm-live-aisfr.aswo.net/ProductManagement/action/login.do?singlelogin=true&app=MobileViewStartPage"
USER_LOGISTIQUE="logistique"
PASS_COMMUN='Aswo+95000'          # mot de passe commun logistique + technicien
USER_TECHNICIEN="technicien"
FIREFOX_BIN="firefox"             # adapter en "firefox-esr" si besoin
### ========================================

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit etre execute en root (sudo bash setup_kiosk_complete.sh)." >&2
  exit 1
fi

echo "==> 1. Verifications preliminaires"

if ! systemctl is-active --quiet lightdm; then
  echo "ERREUR : LightDM n'est pas actif sur ce poste." >&2
  exit 1
fi

if ! command -v "$FIREFOX_BIN" &>/dev/null; then
  echo "ERREUR : la commande '${FIREFOX_BIN}' est introuvable." >&2
  echo "Installe Firefox avant de relancer ce script, ou adapte FIREFOX_BIN." >&2
  exit 1
fi

apt update
apt install -y unclutter x11-xserver-utils openssh-server || true

echo "==> 2. Creation des utilisateurs"

if ! id "$USER_LOGISTIQUE" &>/dev/null; then
  useradd -m -s /bin/bash "$USER_LOGISTIQUE"
fi
echo "${USER_LOGISTIQUE}:${PASS_COMMUN}" | chpasswd
gpasswd -d "$USER_LOGISTIQUE" sudo 2>/dev/null || true

if ! id "$USER_TECHNICIEN" &>/dev/null; then
  useradd -m -s /bin/bash "$USER_TECHNICIEN"
fi
echo "${USER_TECHNICIEN}:${PASS_COMMUN}" | chpasswd
usermod -aG sudo "$USER_TECHNICIEN"

echo "==> 3. Configuration sudo (logistique bloque, technicien autorise)"

cat > /etc/sudoers.d/10-logistique-nosudo <<EOF
${USER_LOGISTIQUE} ALL=(ALL) !ALL
EOF
chmod 440 /etc/sudoers.d/10-logistique-nosudo
visudo -c

echo "==> 4. Configuration SSH (root bloque, technicien autorise)"

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-local-restrictions.conf <<EOF
PermitRootLogin no
AllowUsers ${USER_TECHNICIEN}
EOF
systemctl restart ssh || systemctl restart sshd || true

echo "==> 5. Politiques Firefox (extensions/themes bloques + redirection nouvel onglet)"

mkdir -p /etc/firefox/policies
mkdir -p /usr/lib/firefox/distribution

POLICIES_JSON=$(cat <<JSONEOF
{
  "policies": {
    "DisableAppUpdate": true,
    "DisableSystemAddonUpdate": true,
    "DisableTelemetry": true,
    "DisablePocket": true,
    "DisableFirefoxAccounts": true,
    "DisableFirefoxScreenshots": true,
    "DisableSetDesktopBackground": true,
    "DisableDeveloperTools": true,
    "DisableFeedbackCommands": true,
    "DisableForgetButton": true,
    "DisableMasterPasswordCreation": true,
    "DisablePasswordReveal": true,
    "DisableProfileImport": true,
    "DisableProfileRefresh": true,
    "BlockAboutAddons": true,
    "BlockAboutConfig": true,
    "BlockAboutProfiles": true,
    "BlockAboutSupport": true,
    "NoDefaultBookmarks": true,
    "DisplayBookmarksToolbar": "never",
    "DisplayMenuBar": "never",
    "DontCheckDefaultBrowser": true,
    "OfferToSaveLogins": false,
    "PasswordManagerEnabled": false,
    "ExtensionSettings": {
      "*": {
        "installation_mode": "blocked",
        "blocked_install_message": "Installation des extensions desactivee sur ce poste."
      }
    },
    "Homepage": {
      "URL": "${KIOSK_URL}",
      "Locked": true,
      "StartPage": "homepage"
    },
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "UserMessaging": {
      "WhatsNew": false,
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "UrlbarInterventions": false,
      "SkipOnboarding": true
    },
    "Preferences": {
      "browser.newtab.url": {
        "Value": "${KIOSK_URL}",
        "Status": "locked"
      },
      "browser.newtabpage.activity-stream.enabled": {
        "Value": false,
        "Status": "locked"
      },
      "toolkit.legacyUserProfileCustomizations.stylesheets": {
        "Value": true,
        "Status": "locked"
      }
    }
  }
}
JSONEOF
)

echo "$POLICIES_JSON" > /etc/firefox/policies/policies.json
echo "$POLICIES_JSON" > /usr/lib/firefox/distribution/policies.json

# Validation de la syntaxe JSON (arrete le script si erreur)
python3 -m json.tool /etc/firefox/policies/policies.json > /dev/null

echo "==> 6. Session graphique kiosque pour logistique"

cat > /home/${USER_LOGISTIQUE}/kiosk.sh <<EOF
#!/bin/bash
sleep 5
xset s off
xset -dpms
xset s noblank
unclutter -idle 1 -root &

while true; do
  ${FIREFOX_BIN} --no-remote "${KIOSK_URL}"
  sleep 2
done
EOF
chmod +x /home/${USER_LOGISTIQUE}/kiosk.sh
chown ${USER_LOGISTIQUE}:${USER_LOGISTIQUE} /home/${USER_LOGISTIQUE}/kiosk.sh

mkdir -p /home/${USER_LOGISTIQUE}/.config/autostart
cat > /home/${USER_LOGISTIQUE}/.config/autostart/kiosk-firefox.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Kiosk Firefox
Exec=/home/${USER_LOGISTIQUE}/kiosk.sh
X-GNOME-Autostart-enabled=true
NoDisplay=false
EOF

# Script appele par le raccourci clavier Ctrl+T (nouvel onglet force vers l'URL)
cat > /home/${USER_LOGISTIQUE}/new_tab.sh <<EOF
#!/bin/bash
${FIREFOX_BIN} --new-tab "${KIOSK_URL}"
EOF
chmod +x /home/${USER_LOGISTIQUE}/new_tab.sh
chown ${USER_LOGISTIQUE}:${USER_LOGISTIQUE} /home/${USER_LOGISTIQUE}/new_tab.sh

chown -R ${USER_LOGISTIQUE}:${USER_LOGISTIQUE} /home/${USER_LOGISTIQUE}/.config

echo "==> 7. Auto-login LightDM sur le compte logistique (session XFCE existante)"

XFCE_SESSION="xfce"
if [[ -f /usr/share/xsessions/xfce.desktop ]]; then
  XFCE_SESSION="xfce"
elif [[ -f /usr/share/xsessions/xfce4.desktop ]]; then
  XFCE_SESSION="xfce4"
else
  echo "ATTENTION : aucun fichier xfce.desktop / xfce4.desktop trouve." >&2
fi

mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/10-autologin.conf <<EOF
[Seat:*]
autologin-user=${USER_LOGISTIQUE}
autologin-user-timeout=0
autologin-session=${XFCE_SESSION}
user-session=${XFCE_SESSION}
EOF

echo "==> 8. Mecanisme de personnalisation du hostname au clonage"

# Script execute au tout premier demarrage d'un poste clone (voir prepare_image_for_cloning.sh)
cat > /usr/local/bin/first-boot-setup.sh <<'SCRIPTEOF'
#!/bin/bash
MARKER="/etc/first-boot-done"

if [ -f "$MARKER" ]; then
  exit 0
fi

clear
echo "=================================================================="
echo "   Premiere configuration du poste (image nouvellement deployee)"
echo "=================================================================="
echo ""

CURRENT_HOSTNAME="$(hostname)"
echo "Hostname actuel : ${CURRENT_HOSTNAME}"
echo ""

NEW_HOSTNAME=""
while [ -z "$NEW_HOSTNAME" ]; do
  read -r -p "Entrez le nom de ce poste (hostname) : " NEW_HOSTNAME
  if [ -z "$NEW_HOSTNAME" ]; then
    echo "Le hostname ne peut pas etre vide, merci de ressaisir."
  fi
done

echo ""
echo "Application du hostname : ${NEW_HOSTNAME} ..."

hostnamectl set-hostname "$NEW_HOSTNAME"

if grep -q "^127\.0\.1\.1" /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${NEW_HOSTNAME}/" /etc/hosts
else
  echo -e "127.0.1.1\t${NEW_HOSTNAME}" >> /etc/hosts
fi

echo "Regeneration de l'identifiant machine (machine-id) ..."
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup
if [ -d /var/lib/dbus ]; then
  ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

echo "Regeneration des cles hote SSH ..."
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A >/dev/null 2>&1
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

touch "$MARKER"

echo ""
echo "=================================================================="
echo "  Hostname defini sur : ${NEW_HOSTNAME}"
echo "  Ce poste ne redemandera plus jamais cette information."
echo "=================================================================="
sleep 3
SCRIPTEOF
chmod +x /usr/local/bin/first-boot-setup.sh

# Service systemd qui declenche ce script AVANT l'ouverture de session graphique
# (version avec le correctif Plymouth/LightDM valide sur FR-WST177)
cat > /etc/systemd/system/first-boot-hostname.service <<'SERVICEEOF'
[Unit]
Description=Configuration du hostname au premier demarrage (poste clone/deploye)
DefaultDependencies=no
Conflicts=getty@tty1.service plymouth-quit-wait.service plymouth-quit.service
After=systemd-user-sessions.service
Before=getty@tty1.service plymouth-quit-wait.service plymouth-quit.service lightdm.service

[Service]
Type=oneshot
RemainAfterExit=yes
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
ExecStartPre=-/usr/bin/plymouth quit
ExecStart=/usr/local/bin/first-boot-setup.sh

[Install]
WantedBy=graphical.target
SERVICEEOF

systemctl daemon-reload
systemctl enable first-boot-hostname.service

echo "==> Terminé."
echo "=================================================================="
echo "Résumé :"
echo " - Redémarre le poste (reboot) pour activer l'auto-login."
echo " - Firefox s'ouvre en fenêtre normale sur :"
echo "     ${KIOSK_URL}"
echo " - Se relance automatiquement s'il est fermé."
echo " - SSH : root refusé, seul '${USER_TECHNICIEN}' peut se connecter."
echo " - sudo : actif uniquement pour '${USER_TECHNICIEN}'."
echo " - Mot de passe identique pour les deux comptes."
echo " - Mécanisme de hostname au clonage : installé et activé."
echo ""
echo "ÉTAPES MANUELLES RESTANTES (à faire UNE FOIS, après le 1er reboot,"
echo "en session graphique logistique) :"
echo ""
echo " A) Raccourci clavier Ctrl+T -> nouvel onglet vers l'URL :"
echo "    Menu Applications > Paramètres > Clavier > Raccourcis d'application"
echo "    Ajouter : /home/${USER_LOGISTIQUE}/new_tab.sh"
echo "    Assigner la combinaison : Ctrl+T"
echo ""
echo " B) Masquer le bouton '+' (nouvel onglet natif Firefox) :"
echo "    1. Trouver le nom du profil actif :"
echo "       cat /home/${USER_LOGISTIQUE}/.mozilla/firefox/profiles.ini"
echo "       (chercher la ligne Default=xxxxxxxx.default-release)"
echo "    2. Créer le fichier CSS (remplacer <PROFIL> par le nom trouvé) :"
echo "       mkdir -p /home/${USER_LOGISTIQUE}/.mozilla/firefox/<PROFIL>/chrome"
echo "       cat > /home/${USER_LOGISTIQUE}/.mozilla/firefox/<PROFIL>/chrome/userChrome.css << 'CSS'"
echo "       .tabs-newtab-button { display: none !important; }"
echo "       #tabs-newtab-button { display: none !important; }"
echo "       #new-tab-button { display: none !important; }"
echo "       CSS"
echo "       chown -R ${USER_LOGISTIQUE}:${USER_LOGISTIQUE} /home/${USER_LOGISTIQUE}/.mozilla"
echo "    3. Relancer Firefox : sudo pkill firefox"
echo ""
echo " C) Si le site cible utilise un certificat HTTPS auto-signé/interne :"
echo "    ouvrir Firefox sur l'URL, cliquer 'Advanced' puis accepter"
echo "    l'exception de sécurité. Cette exception sera capturée dans"
echo "    l'image et héritée par tous les postes clonés."
echo ""
echo " NB : ces réglages ne sont pas automatisables de manière fiable"
echo " (GUI uniquement / nom de profil Firefox généré aléatoirement)."
echo ""
echo "ENSUITE, JUSTE AVANT DE CAPTURER L'IMAGE DISQUE :"
echo "   sudo bash prepare_image_for_cloning.sh"
echo "   (nettoie le marqueur de premier démarrage + le machine-id)"
echo "   puis : sudo shutdown now"
echo "=================================================================="
