#!/bin/bash

# Description des variables :
# $nomOriginal = nom complet rep ou fichier original
# $pathOriginal = chemin du repertoire original
# $nomModif = nom complet rep ou fichier modifié
# $pathModif = chemin du repertoire modifié
# $nomArgModif = nom dernier argument modifié
# baseName = chemin du fichier sans .ext
# $ext = extension du fichier le cas échéant sinon , renvoie le chemin complet du fichier.

# variables a ajuster :
modif_activ=false # mettre : true pour appliquer les modifications , false pour visualiser les noms sans les modifier
all_spaces=false # mettre : true pour remplacer tous les espaces partout dans les noms de dossiers et de fichiers
execDir="" # Pour appliquer dans un dossier specifique , mettre le chemin ABSOLU du dossier ici .

#### FIN ####

shopt -s globstar

clean_complete_name() {
    local baseName="$1"

    # Nettoyage des espaces (début, fin, autour des /, multiples)
    baseName=$(printf '%s' "$baseName" | sed -E '
    s/^[[:space:]]+//;
    s/[[:space:]]+$//;
    s/[[:space:]]*\/[[:space:]]*/\//g;
    s/[[:space:]]+/ /g
    ')
    # Remplacement des caractères interdits
    if test "$all_spaces" = true; then
        baseName=$(printf '%s' "$baseName" | tr '><"|?*\\ :' '_________')
    else
        baseName=$(printf '%s' "$baseName" | tr '><"|?*\\:'  '________')
    fi

    printf '%s\n' "$baseName"
}

### Liste des fichiers exclus
Exclus=( CON PRN aux NUL COM{1..9} LPT{1..9} CLOCK$ )
declare -i LongPath=0 NbRepScanned=0 NbFileScanned=0 NbRepModified=0 NbFileModified=0 NbRepNOTModified=0 NbFileNOTModified=0; Debut=$(date +%s);
echo "liste des erreur ( fichiers ou dossiers ) n ' ayant pas pu etre modifiés :" > /tmp/error.log
echo "-------------------" > /tmp/modifs

for nomOriginal in "${execDir:=$PWD}"/**/*; do
    #echo;
    #echo "nomOriginal='$nomOriginal'"
    if test -L "$nomOriginal"; then
        NbFileNOTModified+=1
        echo "$NbFileNOTModified ce fichier est un lien : impossible de renommer '$nomOriginal'" >> /tmp/error.log
        echo "le fichier '$nomOriginal' est un lien : non traité"
        nomModif="$nomOriginal"
        continue
    elif test -f "$nomOriginal"; then
        NbFileScanned+=1
        ext=${nomOriginal##*.} # get extension without filename
        if test "$nomOriginal" != "$ext"; then
            baseName="${nomOriginal%.*}" # get filename without extension
            baseName=$(clean_complete_name "$baseName")
            ext=$(clean_complete_name "$ext")
            nomModif="$baseName.$ext"
        else
            nomModif="$nomOriginal"
        fi
    else
        NbRepScanned+=1
        nomModif=$(clean_complete_name "$nomOriginal")
    fi

    #echo "nomModif='$nomModif'"
    nomArgModif=$(echo "$nomModif" | grep -o '[^/]*$') # Récupére le dernier argument
    #echo "nomArgModif='$nomArgModif'"
    if [[ "${Exclus[*]}" ==  *" $nomArgModif "*  ]]; then nomModif+="_"; fi # Vérifions si le nom n'est pas interdit.

    # le nom du chemin ne doit pas dépasser 256 en standard , et chemin étendu 32767 max , commence par "\\?\" .
    if (( "${#nomArgModif}" >= 256 || "${#nomModif}" >= 32767 )) ; then # Vérifions si la longueur n'est pas excessive
        LongPath+=1
        echo "chemin de fichier ou de dossier trop long ! $LongPath : $nomModif" >> /tmp/error.log
    fi

    if [[ "$nomOriginal" != "$nomModif" ]]; then # si il y a un changement a effectuer
        if test -d "$nomOriginal"; then # si c' est un dossier
            if test -e "$nomModif"; then # on verifie si il existe un dossier du meme nom avant de renommer et si il est modifiable
                NbRepNOTModified+=1
                echo "$NbRepNOTModified un dossier du meme nom existe deja : impossible de renommer '$nomOriginal' en '$nomModif'" >> /tmp/error.log
            elif test ! -w "$nomOriginal"; then
                NbRepNOTModified+=1
                echo "$NbRepNOTModified permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" >> /tmp/error.log
            else # si pas de dossier du meme nom , on renomme
                if test "$modif_activ" = true; then
                    mkdir -p "$nomModif"
                    echo "on renomme le dossier : mkdir '$nomOriginal' ==> '$nomModif'"
                    NbRepModified+=1
                    echo "$NbRepModified CREER_REP : mkdir '$nomModif'" >> /tmp/modifs
                fi
            fi
        elif test -f "$nomOriginal" ; then # si c est un fichier
            if test -e "$nomModif"; then # on verifie si il existe un fichier du meme nom avant de renommer et s ' il est modifiable
                NbFileNOTModified+=1
                echo "$NbFileNOTModified un fichier du meme nom existe deja : impossible de renommer '$nomOriginal' en '$nomModif'" >> /tmp/error.log
            elif test ! -w "$nomOriginal"; then
                NbFileNOTModified+=1
                echo "$NbFileNOTModified : permission refusée : impossible de renommer '$nomOriginal' en '$nomModif'" >> /tmp/error.log
            else # si pas de fichier du meme nom , on renomme
                pathOriginal=${nomOriginal%/*} # chemin du repertoire original
                pathModif=${nomModif%/*} # chemin apres modif
                if [[ "$pathOriginal" != "$pathModif" ]]; then # si les chemins sont differents , c' est que l' arborescence a été modifiée :
                    nomModif="$pathModif"/"$nomArgModif" # dans ce cas on utilise l' arborescence modifiée precedemment + le nom modifié du dernier argument pour la destination
                fi
                echo "renommage du fichier : mv '$nomOriginal' ==> '$nomModif'"
                if test "$modif_activ" = true; then
                    mv "$nomOriginal" "$nomModif"
                    NbFileModified+=1
                    echo "$NbFileModified RENOM : mv '$nomOriginal' en : '$nomModif'" >> /tmp/modifs
                fi
            fi
        fi
    fi
done

echo "$NbRepScanned dossiers et $NbFileScanned fichiers traités, $NbRepModified répertoires modifiés, $NbFileModified fichiers modifiés , le tout en $(($(date +%s)-Debut)) secondes."
echo;
(( NbFileModified || NbRepModified )) && echo "liste des dossiers et fichiers modifiés dans '/tmp/modifs'"
(( NbRepModified )) && echo "pour supprimer les dossiers vides , copiez collez la commande suivante : find '${execDir:=$PWD}' -type d -empty -delete"

if (( NbFileNOTModified || NbRepNOTModified )); then
    echo;
    echo "$NbFileNOTModified fichiers , $NbRepNOTModified répertoires n ' ayant pas pu etre modifiés"
    echo "liste des erreurs dans '/tmp/error.log'"
    echo;
fi
(( LongPath )) && echo "vous avez $LongPath répertoires de taille trop importante. Voir le détail dans /tmp/error.log"
