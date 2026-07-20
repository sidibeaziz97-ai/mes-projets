#!/bin/bash
#
# prepare_image_for_cloning.sh
# ------------------------------------------------------------
# A LANCER UNE SEULE FOIS SUR LE POSTE "MODELE" (celui que tu vas
# capturer avec Clonezilla/FOG/dd/etc.), JUSTE AVANT DE FAIRE LA
# CAPTURE DE L'IMAGE. Ne PAS lancer ce script sur un poste deja
# clone/deploye.
#
# Ce script installe le mecanisme qui fera qu'a chaque premier
# demarrage d'un POSTE CLONE (obtenu a partir de cette image), un
# ecran demandera le hostname avant l'ouverture de session.
#
# A executer en root :
#   sudo bash prepare_image_for_cloning.sh
# ------------------------------------------------------------

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit etre execute en root." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 1. Installation du script de premier demarrage"
cp "${SCRIPT_DIR}/first-boot-setup.sh" /usr/local/bin/first-boot-setup.sh
chmod +x /usr/local/bin/first-boot-setup.sh

echo "==> 2. Installation du service systemd associe"
cp "${SCRIPT_DIR}/first-boot-hostname.service" /etc/systemd/system/first-boot-hostname.service
systemctl daemon-reload
systemctl enable first-boot-hostname.service

echo "==> 3. Nettoyage pour la capture (IMPORTANT)"

# Supprimer le marqueur s'il existe deja (sinon aucun poste clone ne
# redemandera le hostname, puisque le marqueur serait deja present
# dans l'image capturee)
rm -f /etc/first-boot-done

# Vider le machine-id : systemd le regenerera automatiquement, mais
# on le fait aussi ici en filet de securite supplementaire
truncate -s 0 /etc/machine-id

echo ""
echo "=================================================================="
echo " Pret pour la capture de l'image."
echo ""
echo " PROCHAINES ETAPES :"
echo "  1. Eteindre proprement ce poste (shutdown now), SANS redemarrer"
echo "     (un redemarrage recreerait un machine-id et pourrait faire"
echo "     tourner le service avant la capture)."
echo "  2. Capturer l'image disque avec ton outil habituel (Clonezilla,"
echo "     FOG, dd, etc.)."
echo "  3. Deployer cette image sur les autres postes."
echo ""
echo " A chaque premier demarrage d'un poste ainsi clone, un ecran"
echo " demandera le hostname avant l'ouverture de session graphique,"
echo " puis ne redemandera plus jamais rien ensuite."
echo "=================================================================="
