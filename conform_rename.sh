#!/bin/bash

# Description des variables :
# $nomOriginal = nom complet rep ou fichier original
# $pathOriginal = chemin du repertoire original
# $nomModif = nom complet rep ou fichier modifié
# $pathModif = chemin du repertoire modifié
# $nomArgModif = nom dernier argument modifié

# variables a ajuster :
modif_activ=false # mettre : true pour appliquer les modifications , false pour visualiser les noms sans les modifier
all_spaces=false # mettre : true pour remplacer tous les espaces partout dans les noms de dossiers et de fichiers
execDir="" # Pour appliquer dans un dossier specifique , mettre le chemin absolu du dossier ici .
#### FIN ####

shopt -s globstar

### Liste des fichiers exclus
Exclus=(CON PRN aux NUL COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9 LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9)
declare -i LongPath=0 NbScan=0 NbRep=0 NbFile=0 NbRepModified=0 NbFileModified=0 NbRepNOTModified=0 NbFileNOTModified=0; Debut=$(date +%s);
echo "liste des erreur ( fichiers ou dossiers ) n ' ayant pas pu etre modifiés :" > /tmp/error.log
echo "-------------------" > /tmp/modifs

for nomOriginal in "${execDir:=$PWD}/"**/*; do
    NbScan+=1
    nomModif=$(echo $nomOriginal | sed 's@ */ *@/@g') # traitement des espaces en debut et fin du nom
    # remplacement d'un maxima de caractères interdits par windows :  ><\:"|?* par " _ " + les espaces ( uniques et restant ) dans les noms .
    if [ $all_spaces = true ]; then
        nomModif=$(echo $nomModif | tr '><"|?*\\ :'    '_________%') # version all spaces .
    else
        nomModif=$(echo $nomModif | tr '><"|?*\\:'    '_______%') # echappement de "\" par le meme signe donc 2 \\ pour qu un soit remplacé
    fi

    nomArgModif=$(echo "$nomModif" | grep -o '[^/]*$' ) # Récupére le dernier argument
    if [[ " ${Exclus[*]} " ==  *" $nomArgModif "*  ]]; then nomModif+=_ ; fi # Vérifions si le nom n'est pas interdit.

    if [[ "${#nomArgModif}" -ge 248 || "${#nomModif}"  -ge 32384 ]] ; then # Vérifions si la longueur n'est pas excessive
        LongPath=$((LongPath+1))
        echo "chemin de fichier / dossier trop long ! $LongPath : $nomModif" >> /tmp/error.log
    fi

    if [[ "$nomOriginal" != "$nomModif" ]]; then # si il y a un changement a effectuer
        if test -d "$nomOriginal" ; then # si c' est un dossier
            NbRep+=1
            if test -e "$nomModif" ; then # on verifie si il existe un dossier du meme nom avant de renommer
                NbRepNOTModified+=1
                echo "$NbRep un dossier du meme nom existe deja : $nomModif impossible de renommer $nomOriginal" >> /tmp/error.log
            else # si pas de dossier du meme nom , on renomme
                if [ "$modif_activ" = true ] ; then
                    mkdir -p "$nomModif"
                    echo "on va renommer le répertoire avec la commande suivante : mkdir $nomOriginal => $nomModif"
                    if test -e "$nomModif" ; then # si la creation du repertoire a reussi , on enregistre
                        echo "$NbScan CREER_REP : mkdir $nomModif" >> /tmp/modifs
                        NbRepModified+=1
                    else
                        NbRepNOTModified+=1
                        echo "$NbScan erreur inconnue pour repertoire : $nomOriginal" >> /tmp/error.log
                    fi
                fi
            fi
        elif test -f "$nomOriginal" ; then # si c est un fichier
            NbFile+=1
            if test -e "$nomModif" ; then # on verifie si il existe un fichier du meme nom avant de renommer
                NbFileNOTModified+=1
                echo "$NbScan un fichier du meme nom existe deja : $nomModif impossible de renommer $nomOriginal" >> /tmp/error.log
            else # si pas de fichier du meme nom , on renomme
                pathOriginal=${nomOriginal%/*} # chemin du repertoire original
                pathModif=${nomModif%/*} # chemin apres modif
                if [[ "$pathOriginal" != "$pathModif" ]]; then # si les chemins sont differents , c' est que l' arborescence a été modifiée :
                    nomModif="$pathModif"/"$nomArgModif" # dans ce cas on utilise l' arborescence modifiée precedemment + le nom modifié du dernier argument pour la destination
                fi
                    echo "renommage du fichier : mv $nomOriginal ==> $nomModif"
                if [ "$modif_activ" = true ] ; then
                    mv "$nomOriginal" "$nomModif"
                if test -e "$nomModif" ; then # on verifie que le fichier renommé existe bien , si le fichier existe on incremente et on enregistre
                    echo "$NbScan RENOM : mv $nomOriginal en : $nomModif" >> /tmp/modifs
                    NbFileModified+=1
                else
                    NbFileNOTModified+=1
                    echo "$NbScan erreur inconnue pour fichier : $nomOriginal" >> /tmp/error.log
                fi
            fi
        fi
        else
            NbFileModified+=1
            echo "$NbScan erreur inconnue pour : $nomOriginal" >> /tmp/error.log
        fi
    fi

done

echo ""
echo "$NbScan répertoires et fichiers traités, $NbRepModified répertoires modifiés, $NbFileModified fichiers modifiés"
echo "$NbFileNOTModified fichiers , $NbRepNOTModified répertoires n ' ayant pas pu etre modifiés , le tout en $(($(date +%s)-Debut)) secondes."
echo ""
echo "liste des fichiers modifiés dans '/tmp/modifs'"
echo "liste des erreurs dans '/tmp/error.log'"
echo ""
if [[ "$LongPath" -ne 0 ]]; then echo "vous avez $LongPath répertoires de taille trop importante. Voir le détail dans /tmp/error.log" ; fi

echo "pour supprimer les dossiers vides , copiez collez la commande suivante : find '${execDir:=$PWD}' -type d -empty -delete"
