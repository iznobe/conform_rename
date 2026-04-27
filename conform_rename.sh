#!/bin/bash

# Description des variables :
# $nomOriginal = nom complet rep ou fichier original
# $pathOriginal = chemin du repertoire original
# $nomModif = nom complet rep ou fichier modifié
# $pathModif = chemin du repertoire modifié
# $cleanFileName = nom fichier nettoyé
# FPNWE = chemin du fichier complet sans .ext = Full Path Name Without Extension
# $ext = extension du fichier le cas échéant sinon , renvoie le chemin complet du fichier.

# --- Configuration ---
modif_activ=false  # true pour appliquer les modifications
execDir=""         # Chemin ABSOLU du dossier cible (vide = PWD)
#### FIN ####

# --- Variables globales ---
declare -i LongPath=0 NbNOTScanned=0 NbRepScanned=0 NbFileScanned=0 NbRepModified=0 NbFileModified=0 NbRepNOTModified=0 NbFileNOTModified=0; Debut=$(date +%s);
declare log_error="/tmp/error.log" log_modifs="/tmp/modifs"
### Liste des fichiers exclus
Exclus=( CON PRN AUX NUL NULL COM{0..9} LPT{0..9} COM¹ COM² COM³ LPT¹ LPT² LPT³ CLOCK$ )
# --- Initialisation ---
shopt -s globstar nullglob
echo "liste des erreurs ( fichiers ou dossiers ) n ' ayant pas pu etre modifiés :" > "$log_error"
echo "-------------------" > "$log_modifs"

check_exclu() {
	local name="$1"
	if [[ " ${Exclus[*]} " == *" $(echo "${name##*/}" | tr '[:lower:]' '[:upper:]') "* ]]; then name+="_"; fi
	printf '%s\n' "$name"
}

clean_name() { # Nettoie un nom de fichier/dossier
  printf '%s' "$1" | sed -E '
    s/^[[:space:]]+|[[:space:]]+$//g;
    s/[[:space:]]*\/[[:space:]]*/\//g;
    s/[[:space:]]+/ /g;
    s/[[:space:]]*\.[[:space:]]*([^.]+)$/.\1/;
    s/[^[:print:]]|['\''><"|?*\\:]/_/g
    '
}

for nomOriginal in "${execDir:=$PWD}"/**/*; do
	if test -L "$nomOriginal"; then
		((NbNOTScanned++))
		continue
	elif test -f "$nomOriginal"; then
		((NbFileScanned++))
		ext=${nomOriginal##*.} # get extension without filename
		if test "$nomOriginal" != "$ext"; then # si le fichier comporte une extension
			FPNWE="${nomOriginal%.*}" # get filename without extension
			FPNWE=$(clean_name "$FPNWE")
			FPNWE=$(check_exclu "$FPNWE")

			ext=$(clean_name "$ext")
			nomModif="$FPNWE.$ext"
		else # si le fichier ne comporte pas d ' extension
			nomModif=$(clean_name "$nomOriginal")
			nomModif=$(check_exclu "$nomModif")
		fi
	else
		((NbRepScanned++))
		nomModif=$(clean_name "$nomOriginal")
		nomModif=$(check_exclu "$nomModif")
	fi

	if [[ "$nomOriginal" != "$nomModif" ]]; then # si il y a un changement a effectuer
		# le nom du chemin ne doit pas dépasser 256 en standard , et chemin étendu 32767 max , prefixe windows = "\\?\"
		if (( "${#nomModif}" >= 256 )) ; then # Vérifions si la longueur n'est pas excessive
			((LongPath++))
			echo "Le nom de chemin de fichier est trop long ! impossible de renommer '$nomOriginal' en '$nomModif'" >> "$log_error"
		fi

		if test -d "$nomOriginal"; then # si c' est un dossier
			if test ! -w "$(realpath "${nomOriginal}"/..)"; then # on verifie si le dossier parent est modifiable
				((NbRepNOTModified++))
				echo "permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'"
				echo "$NbRepNOTModified permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" >> "$log_error"
			else # eviter les doublons et renommer correctement quand meme :
				suffix=0
				while test -e "$nomModif"; do # Tant que le dossier cible existe déjà
					nomModif="${nomModif}_${suffix}"
					((suffix++))
				done

				echo "dossier renommé : mkdir '$nomOriginal' ==> '$nomModif'"
				if test "$modif_activ" = true; then
					mkdir -pv "$nomModif"
					((NbRepModified++))
					echo "$NbRepModified CREER_REP : mkdir '$nomModif'" >> "$log_modifs"
				fi
			fi
		elif test -f "$nomOriginal" ; then # si c est un fichier
			if test ! -w "$(dirname "${nomOriginal}")"; then # on verifie si le dossier parent est modifiable
				((NbFileNOTModified++))
				echo "permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'"
				echo "$NbFileNOTModified : permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" >> "$log_error"
			else
				pathOriginal=${nomOriginal%/*} # chemin du repertoire original
				pathModif=${nomModif%/*} # chemin apres modif
				if [[ "$pathOriginal" != "$pathModif" ]]; then # si les chemins sont differents , c' est que l' arborescence a été modifiée :
					nomModif="$pathModif"/"${nomModif##*/}" # dans ce cas on utilise l' arborescence modifiée precedemment + le nom modifié du dernier argument pour la destination
				fi

				# eviter les doublons et renommer correctement quand meme :
				directory="${nomModif%/*}"
				cleanFileName="${nomModif##*/}"
				base="$cleanFileName"
				ext=""
				suffix=0

				if [[ "$cleanFileName" == .* ]]; then
					base="${cleanFileName:1}" # Fichier caché (ex: .bash_profile) , Enlève le point initial
					if [[ "$base" == *.* ]]; then
						ext=".${base##*.}"
						base="${base%.*}"
					fi
				else
					if [[ "$cleanFileName" == *.* ]]; then # Fichier normal (ex: fichier.txt)
						ext=".${cleanFileName##*.}"
						base="${cleanFileName%.*}"
					fi
				fi

				while [[ -e "$nomModif" ]]; do
					nomModif="${directory}/${base}_${suffix}${ext}"
					((suffix++))
				done

				echo "renommage du fichier : mv '$nomOriginal' ==> '$nomModif'"
				if test "$modif_activ" = true; then
					mv  "$nomOriginal" "$nomModif"
					NbFileModified+=1
					echo "$NbFileModified RENOM : mv '$nomOriginal' en : '$nomModif'" >> "$log_modifs"
				fi
			fi
		fi
	fi
done

echo;
echo "récapitulatif :"
echo "$NbRepScanned dossiers et $NbFileScanned fichiers traités, $NbRepModified répertoires modifiés, $NbFileModified fichiers modifiés , le tout en $(($(date +%s)-Debut)) secondes."
(( NbNOTScanned )) && echo "$NbNOTScanned non traités."
echo;
(( NbFileModified || NbRepModified )) && echo "Pour voir les modifications : cat '/tmp/modifs'"
(( NbRepModified )) && echo "pour supprimer les dossiers vides , copiez collez la commande suivante : find '${execDir:=$PWD}' -type d -empty -delete"
echo;
if (( NbFileNOTModified || NbRepNOTModified || LongPath)); then
	echo "$NbFileNOTModified fichiers , $NbRepNOTModified répertoires n ' ayant pas pu etre modifiés"
	echo "vous avez $LongPath répertoires de taille trop importante."
	echo "liste des erreurs : cat '$log_error'"
	echo;
fi
