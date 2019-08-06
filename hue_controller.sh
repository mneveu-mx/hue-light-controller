#!/bin/bash
set -e
set -u
set -o pipefail
##### VARIABLES ######
CONFIG_FILE="hue_controller.yml"
MANDATORY_PARAMETERS=( conf_huebridge_ip conf_sensor_name conf_light_name conf_debug conf_hue_api_token conf_store_objects_in_files )
PATH_DATAS="datas"
PATH_STORE_LIGHTS=$PATH_DATAS"/lights"
PATH_STORE_SENSORS=$PATH_DATAS"/sensors"
FILE_INDEX_LIGHTS=$PATH_DATAS"/index_lights.mx"
FILE_INDEX_SENSORS=$PATH_DATAS"/index_sensors.mx"

######################


#Parse YAML : @pkuczynski/parse_yaml.sh
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
	cat example_lights.json \
	| jq -r '.lights | keys[] as $k | "\(.[$k].name)=\($k)"' 1>$1 || (echo "L'index $(basename $1) n'a pas été correctement récupéré ou parsé" && exit 1)
	check_file_is_updated $1 2 
}


get_index_sensors() {
	#curl $HUE_API_URL"/"$1 \
	cat example_sensors.json \
	| jq -r '.sensors | keys[] as $k | "\(.[$k].name)=\($k)"' 1>$1 || (echo "L'index $(basename $1) n'a pas été correctement récupéré ou parsé" && exit 1)
	check_file_is_updated $1 2
}

create_status_file() {
	IFS="="
	while read -r k v
	do
		cat $1 | jq ".$2.\"$v\"" > $3"/"$k
	done < $4
	test $conf_debug -eq 1 && echo $(ls $3 | wc -l)" created file(s) for "$2
}

clean_status_files() {
	rm -rf $1"/*"
}

get_json_value() {
	cat $1 | jq $2
}

get_json_sensor_value() {
	get_json_value $PATH_STORE_SENSORS"/"$conf_sensor_name $1
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
get_index_sensors $FILE_INDEX_SENSORS

test $conf_debug -eq 1 && echo $(cat $FILE_INDEX_LIGHTS);
test $conf_debug -eq 1 && echo $(cat $FILE_INDEX_SENSORS);

echo "Créer 1 fichier statut par équipement Hue"
clean_status_files $PATH_STORE_LIGHTS
create_status_file example_lights.json "lights" $PATH_STORE_LIGHTS $FILE_INDEX_LIGHTS

clean_status_files $PATH_STORE_SENSORS
create_status_file example_sensors.json "sensors" $PATH_STORE_SENSORS $FILE_INDEX_SENSORS

echo "Controller"
test $conf_debug -eq 1 && echo "\""$conf_light_name"\" controlled by \""$conf_sensor_name"\""

echo "Vérification état sensor"
SENSOR_ON=$(get_json_sensor_value ".config.on")
SENSOR_REACHABLE=$(get_json_sensor_value ".config.reachable")
