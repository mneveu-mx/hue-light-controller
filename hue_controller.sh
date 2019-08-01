#!/bin/bash
set -e
set -u
set -o pipefail
##### VARIABLES ######
CONFIG_FILE="hue_controller.yml"
MANDATORY_PARAMETERS=( conf_huebridge_ip conf_sensor_name conf_light_name conf_debug conf_hue_api_token conf_store_objects_in_files )
FILE_INDEX_LIGHTS="datas/index_lights.mx"
FILE_INDEX_SENSORS="datas/index_sensors.mx"

######################


#Parse YAML : @ pkuczynski/parse_yaml.sh
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

verify_param() {
	[[ -z ${!1} ]] \
		&& echo $1 value not present in $CONFIG_FILE, exiting. && exit 1 \
		|| test $conf_debug -eq 1 && echo $1 ":" ${!1};
}

check_file_is_updated() {
	nb=$(find datas/ -name $(basename $1) -mmin -$2 | wc -l)
	test $nb -gt 0 || (echo "L'index $1 n'est pas à jour" && exit 1)
}

get_index_lights() {
	#curl $HUE_API_URL"/"$1 \
	cat example.json \
	| jq -r '.lights | keys[] as $k | "\"\(.[$k].name)\"=\($k)"' 1>$1 || (echo "L'index $(basename $1) n'a pas été correctement récupéré ou parsé" && exit 1)
	check_file_is_updated $1 2 
}


get_index_sensors() {
	#curl $HUE_API_URL"/"$1 \
	cat example.json \
	| jq -r '.sensors | keys[] as $k | "\"\(.[$k].name)\"=\($k)"' 1>$1 || (echo "L'index $(basename $1) n'a pas été correctement récupéré ou parsé" && exit 1)
	check_file_is_updated $1 2
}

echo "Hue controller @MNE_v0.1 : August 2018"

echo "Lecture du fichier de configuration : $CONFIG_FILE"
eval $(parse_yaml $CONFIG_FILE "conf_")
echo "Vérification des paramètres"
for param in "${MANDATORY_PARAMETERS[@]}"
do
	verify_param $param;
done

## Paramètres HUE ##
HUE_API_URL="http://"$conf_huebridge_ip"/api/"$conf_hue_api_token"/"
get_index_lights $FILE_INDEX_LIGHTS
#get_index_sensors $FILE_INDEX_SENSORS

test $conf_debug -eq 1 && echo $(cat $FILE_INDEX_LIGHTS);
test $conf_debug -eq 1 && echo $(cat $FILE_INDEX_SENSORS);
for i in ${INDEX_LIGHTS[@]}; do echo $i; done

echo "Créer 1 fichier statut par équipement Hue"


echo "Récupération de l'état des lumières"
#state_lights_json=$(curl $HUE_API_URL"/lights");

#echo $state_lights_json

echo "Récupération de l'état des détecteurs"
