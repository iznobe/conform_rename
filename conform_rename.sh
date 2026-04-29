#!/bin/bash

# Description des variables :
# $nomOriginal = nom complet rep ou fichier original
# $pathOriginal = chemin du repertoire original
# $nomModif = nom complet rep ou fichier modifié
# $pathModif = chemin du repertoire modifié
# $cleanFileName = nom fichier nettoyé
# FPNWE = chemin du fichier complet sans .ext = Full Path Name Without Extension
# $ext = extension du fichier le cas échéant sinon , renvoie le chemin complet du fichier si pas d' extension.

# --- Configuration ---

modif_activ=false  # true pour appliquer les modifications
execDir=""         # Chemin ABSOLU du dossier cible , vide = dossier de travail du terminal : $PWD

#### FIN ####

# --- Variables globales ---
declare -i count=0 LongPath=0 NbNOTScanned=0 NbRepScanned=0 NbFileScanned=0 NbRepModified=0 NbFileModified=0 NbRepNOTModified=0 NbFileNOTModified=0; Debut=$(date +%s);
declare log_error="/tmp/error.log" log_modifs="/tmp/modifs.log" log_pre_modifs="/tmp/pre_modifs.log"

# --- Initialisation ---
shopt -s globstar nullglob
now=$(date +"%d/%m/%Y %H:%M:%S")
if ! "$modif_activ"; then
	echo "Récapitulatif de la simulation du $now" | tee -a "$log_pre_modifs"
else
	echo "Modifications du $now" | tee -a "$log_modifs"
	echo "liste des erreurs du $now ( fichiers ou dossiers ) n ' ayant pas pu etre modifiés :" | tee -a "$log_error"
fi

clean_name() { # Nettoie un nom de fichier/dossier
	printf '%s' "$1" | awk '
	BEGIN {
		IGNORECASE = 1

		reserved["NUL"]; reserved["NULL"]; reserved["PRN"]; reserved["CON"]; reserved["AUX"]; reserved["CLOCK$"]
		for (i=0;i<=9;i++) { reserved["COM" i]; reserved["LPT" i] }
		reserved["COM¹"]; reserved["COM²"]; reserved["COM³"]
		reserved["LPT¹"]; reserved["LPT²"]; reserved["LPT³"]
	}
	{
		# trim
		gsub(/^[[:space:]]+|[[:space:]]+$/, "")

		# espaces autour /
		gsub(/[[:space:]]*\/[[:space:]]*/, "/")

		# espaces multiples
		gsub(/[[:space:]]+/, " ")

		# caractères interdits + contrôle
		gsub(/['\''"\\:\*\?\"<>\|\001-\037\177]/, "_")

		# suppression points finaux
		sub(/\.+$/, "")

		# nettoyage dernier point
		if (match($0, /[[:space:]]*\.[[:space:]]*([^.]+)$/)) {
			ext = substr($0, RSTART, RLENGTH)
			sub(/^[[:space:]]*\.[[:space:]]*/, ".", ext)
			$0 = substr($0, 1, RSTART-1) ext
		}

		# uniquement des points → vide
		if ($0 ~ /^\.*$/) $0=""

		# basename sans extension
		base = $0
		sub(/\..*$/, "", base)

		if (toupper(base) in reserved) {
			$0 = base "_" substr($0, length(base)+1)
		}

		# vide → NONAME
		if ($0 ~ /^[[:space:]]*$/) $0="NONAME"

			print  # <-- Ici, le print est bien dans le bloc !
		}'
}

while IFS= read -r -d '' nomOriginal; do
	if test -L "$nomOriginal"; then
		((NbNOTScanned++))
		continue
	fi

	pathOriginal="${nomOriginal%/*}" # get original pathname
	file="${nomOriginal##*/}" # get file name or directory name

	if test -f "$nomOriginal"; then
		((NbFileScanned++))
	else
		((NbRepScanned++))
	fi

	nomModif="$pathOriginal/$(clean_name "$file")"

	###############################"

	if [[ "$nomOriginal" != "$nomModif" ]]; then # si il y a un changement a effectuer
		# le nom du chemin ne doit pas dépasser 256 en standard , et chemin étendu 32767 max , prefixe windows = "\\?\"
		if (("${#nomModif}" >= 256)) ; then # Vérifions si la longueur n'est pas excessive
			((LongPath++))
			echo "Le nom de chemin de fichier est trop long ! impossible de renommer '$nomOriginal' en '$nomModif'" >> "$log_error"
		fi

		if test -d "$nomOriginal"; then # si c' est un dossier
			if test ! -w "$(realpath "${nomOriginal}"/..)"; then # on verifie si le dossier parent est modifiable
				((NbRepNOTModified++))
				echo "permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" | tee -a "$log_error"
			else # eviter les doublons et renommer correctement quand meme :

				suffix=0
				while test -e "$nomModif"; do # Tant que le dossier cible existe déjà
					nomModif="${nomModif}_${suffix}"
					((suffix++))
				done

				if "$modif_activ"; then
					mv -v "$nomOriginal" "$nomModif" | tee -a "$log_modifs"
					((NbRepModified++))
				else
          ((count++))
					echo "SIMUL dossier renommé : mv '$nomOriginal' ==> '$nomModif'" | tee -a "$log_pre_modifs"
				fi
			fi

		elif test -f "$nomOriginal" ; then # si c est un fichier
			if test ! -w "$(dirname "${nomOriginal}")"; then # on verifie si le dossier parent est modifiable
				((NbFileNOTModified++))
				echo "permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" | tee -a "$log_error"
			else
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

				if "$modif_activ"; then
					mv -v "$nomOriginal" "$nomModif" | tee -a "$log_modifs"
					NbFileModified+=1
				else
          ((count++))
					echo "SIMUL renommage du fichier : mv '$nomOriginal' ==> '$nomModif'" | tee -a "$log_pre_modifs"
				fi
			fi
		fi
	fi

done < <(find "${execDir:=$PWD}" -depth -print0)

echo;
echo "récapitulatif : "
((count)) && echo "modif count = $count . Voir les modifications prévues : cat '$log_pre_modifs'" && echo
echo "$NbRepScanned dossiers et $NbFileScanned fichiers traités, $NbRepModified répertoires modifiés, $NbFileModified fichiers modifiés , le tout en $(($(date +%s)-Debut)) secondes." && echo;
((NbNOTScanned)) && echo "$NbNOTScanned non traités." && echo;
((NbFileModified || NbRepModified)) && echo "Pour voir les modifications : cat '$log_modifs'"
((NbRepModified)) && echo "pour supprimer les dossiers vides , copiez collez la commande suivante : find '${execDir:=$PWD}' -type d -empty -delete" && echo;
if ((NbFileNOTModified || NbRepNOTModified || LongPath)); then
	echo "$NbFileNOTModified fichiers , $NbRepNOTModified répertoires n ' ayant pas pu etre modifiés"
	echo "vous avez $LongPath répertoires de taille trop importante."
	echo "liste des erreurs : cat '$log_error'"
	echo;
fi#!/bin/bash

# Description des variables :
# $nomOriginal = nom complet rep ou fichier original
# $pathOriginal = chemin du repertoire original
# $nomModif = nom complet rep ou fichier modifié
# $pathModif = chemin du repertoire modifié
# $cleanFileName = nom fichier nettoyé
# FPNWE = chemin du fichier complet sans .ext = Full Path Name Without Extension
# $ext = extension du fichier le cas échéant sinon , renvoie le chemin complet du fichier si pas d' extension.

# --- Configuration ---

modif_activ=false  # true pour appliquer les modifications
execDir=""         # Chemin ABSOLU du dossier cible , vide = dossier de travail du terminal : $PWD

#### FIN ####

# --- Variables globales ---
declare -i count=0 LongPath=0 NbNOTScanned=0 NbRepScanned=0 NbFileScanned=0 NbRepModified=0 NbFileModified=0 NbRepNOTModified=0 NbFileNOTModified=0; Debut=$(date +%s);
declare log_error="/tmp/error.log" log_modifs="/tmp/modifs.log" log_pre_modifs="/tmp/pre_modifs.log"

# --- Initialisation ---
shopt -s globstar nullglob
if ! "$modif_activ"; then
	echo "Récapitulatif de la simulation du $(date +"-%d-%m-%Y-%H-%M-%S")" >> "$log_pre_modifs"
else
	echo "Modifications du $(date +"-%d-%m-%Y-%H-%M-%S")" >> "$log_modifs"
	echo "liste des erreurs du $(date +"-%d-%m-%Y-%H-%M-%S") ( fichiers ou dossiers ) n ' ayant pas pu etre modifiés :" >> "$log_error"
fi

clean_name() { # Nettoie un nom de fichier/dossier
	printf '%s' "$1" | awk '
	BEGIN {
		IGNORECASE = 1

		reserved["NUL"]; reserved["NULL"]; reserved["PRN"]; reserved["CON"]; reserved["AUX"]; reserved["CLOCK$"]
		for (i=0;i<=9;i++) { reserved["COM" i]; reserved["LPT" i] }
		reserved["COM¹"]; reserved["COM²"]; reserved["COM³"]
		reserved["LPT¹"]; reserved["LPT²"]; reserved["LPT³"]
	}
	{
		# trim
		gsub(/^[[:space:]]+|[[:space:]]+$/, "")

		# espaces autour /
		gsub(/[[:space:]]*\/[[:space:]]*/, "/")

		# espaces multiples
		gsub(/[[:space:]]+/, " ")

		# caractères interdits + contrôle
		gsub(/['\''"\\:\*\?\"<>\|\001-\037\177]/, "_")

		# suppression points finaux
		sub(/\.+$/, "")

		# nettoyage dernier point
		if (match($0, /[[:space:]]*\.[[:space:]]*([^.]+)$/)) {
			ext = substr($0, RSTART, RLENGTH)
			sub(/^[[:space:]]*\.[[:space:]]*/, ".", ext)
			$0 = substr($0, 1, RSTART-1) ext
		}

		# uniquement des points → vide
		if ($0 ~ /^\.*$/) $0=""

		# basename sans extension
		base = $0
		sub(/\..*$/, "", base)

		if (toupper(base) in reserved) {
			$0 = base "_" substr($0, length(base)+1)
		}

		# vide → NONAME
		if ($0 ~ /^[[:space:]]*$/) $0="NONAME"

			print  # <-- Ici, le print est bien dans le bloc !
		}'
}

while IFS= read -r -d '' nomOriginal; do
	if test -L "$nomOriginal"; then
		((NbNOTScanned++))
		continue
	fi

	pathOriginal="${nomOriginal%/*}" # get original pathname
	file="${nomOriginal##*/}" # get file name or directory name

	if test -f "$nomOriginal"; then
		((NbFileScanned++))
	else
		((NbRepScanned++))
	fi

	nomModif="$pathOriginal/$(clean_name "$file")"

	###############################"

	if [[ "$nomOriginal" != "$nomModif" ]]; then # si il y a un changement a effectuer
		# le nom du chemin ne doit pas dépasser 256 en standard , et chemin étendu 32767 max , prefixe windows = "\\?\"
		if (("${#nomModif}" >= 256)) ; then # Vérifions si la longueur n'est pas excessive
			((LongPath++))
			echo "Le nom de chemin de fichier est trop long ! impossible de renommer '$nomOriginal' en '$nomModif'" >> "$log_error"
		fi

		if test -d "$nomOriginal"; then # si c' est un dossier
			if test ! -w "$(realpath "${nomOriginal}"/..)"; then # on verifie si le dossier parent est modifiable
				((NbRepNOTModified++))
				echo "permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" | tee -a "$log_error"
			else # eviter les doublons et renommer correctement quand meme :

				suffix=0
				while test -e "$nomModif"; do # Tant que le dossier cible existe déjà
					nomModif="${nomModif}_${suffix}"
					((suffix++))
				done

				if "$modif_activ"; then
					mv -v "$nomOriginal" "$nomModif" | tee -a "$log_modifs"
					((NbRepModified++))
				else
          ((count++))
					echo "SIMUL dossier renommé : mv '$nomOriginal' ==> '$nomModif'" | tee -a "$log_pre_modifs"
				fi
			fi

		elif test -f "$nomOriginal" ; then # si c est un fichier
			if test ! -w "$(dirname "${nomOriginal}")"; then # on verifie si le dossier parent est modifiable
				((NbFileNOTModified++))
				echo "permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" | tee -a "$log_error"
			else
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

				if "$modif_activ"; then
					mv -v "$nomOriginal" "$nomModif" | tee -a "$log_modifs"
					NbFileModified+=1
				else
          ((count++))
					echo "SIMUL renommage du fichier : mv '$nomOriginal' ==> '$nomModif'" | tee -a "$log_pre_modifs"
				fi
			fi
		fi
	fi

done < <(find "${execDir:=$PWD}" -depth -print0)

echo;
echo "récapitulatif : "
((count)) && echo "modif count = $count . Voir les modifications prévues : cat '$log_pre_modifs'" && echo
echo "$NbRepScanned dossiers et $NbFileScanned fichiers traités, $NbRepModified répertoires modifiés, $NbFileModified fichiers modifiés , le tout en $(($(date +%s)-Debut)) secondes." && echo;
((NbNOTScanned)) && echo "$NbNOTScanned non traités." && echo;
((NbFileModified || NbRepModified)) && echo "Pour voir les modifications : cat '$log_modifs'"
((NbRepModified)) && echo "pour supprimer les dossiers vides , copiez collez la commande suivante : find '${execDir:=$PWD}' -type d -empty -delete" && echo;
if ((NbFileNOTModified || NbRepNOTModified || LongPath)); then
	echo "$NbFileNOTModified fichiers , $NbRepNOTModified répertoires n ' ayant pas pu etre modifiés"
	echo "vous avez $LongPath répertoires de taille trop importante."
	echo "liste des erreurs : cat '$log_error'"
	echo;
fi
