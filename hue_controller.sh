#!/bin/bash
set -e
set -u
set -o pipefail
##### VARIABLES ######
CONFIG_FILE="hue_controller.yml"
MANDATORY_PARAMETERS=( conf_huebridge_ip conf_sensor_name conf_light_name conf_debug conf_hue_api_token conf_store_objects_in_files conf_seconds_between_detection )
PATH_DATAS="datas"
PATH_STORE_LIGHTS=$PATH_DATAS"/lights"
PATH_STORE_SENSORS=$PATH_DATAS"/sensors"
FILE_STORE_HISTORY_DETECTED=$PATH_DATAS"/detected_history.log"
FILE_INDEX_LIGHTS=$PATH_DATAS"/index_lights.mx"
FILE_INDEX_SENSORS=$PATH_DATAS"/index_sensors.mx"
TIMESTAMP_LAST_DETECTED=0


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
	test $conf_debug -eq 1 && echo "Delete files from "$1"/*"
	rm -rf $1"/*"
}

get_json_value() {
	cat $1 | jq $2
}

get_json_sensor_value() {
	get_json_value $PATH_STORE_SENSORS"/"$conf_sensor_name $1
}

log_time() {
	echo $(date -d@$1) > $FILE_STORE_HISTORY_DETECTED
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

clean_status_files $PATH_STORE_LIGHTS
clean_status_files $PATH_STORE_SENSORS

echo "Controller"
test $conf_debug -eq 1 && echo "\""$conf_light_name"\" controlled by \""$conf_sensor_name"\""

echo "Vérification état sensor"
while true
do
	sleep 0.5
	#curl
	create_status_file example_lights.json "lights" $PATH_STORE_LIGHTS $FILE_INDEX_LIGHTS
	create_status_file example_sensors.json "sensors" $PATH_STORE_SENSORS $FILE_INDEX_SENSORS

	SENSOR_ON=$(get_json_sensor_value ".config.on")
	SENSOR_REACHABLE=$(get_json_sensor_value ".config.reachable")
	SENSOR_LAST_DETECTED_DATE=$(get_json_sensor_value ".state.lastupdated" | tr -d '"')
	SENSOR_LAST_DETECTED=$(date -d$SENSOR_LAST_DETECTED_DATE +%s)
	
	#LIGHT_REACHEABLE=
	#LIGHT_ON=
	test $conf_debug -eq 1 && echo "sensor[on]:"$SENSOR_ON
	test $conf_debug -eq 1 && echo "sensor[reachable]:"$SENSOR_REACHABLE
	test $conf_debug -eq 1 && echo "sensor[lastupdated]:"$SENSOR_LAST_DETECTED_DATE"/"$SENSOR_LAST_DETECTED
	#test $conf_debug -eq 1 && echo "light[reachable]:"$LIGHT_REACHABLE
	#test $conf_debug -eq 1 && echo "light[on]:'$LIGHT_ON

	if [[ $TIMESTAMP_LAST_DETECTED -eq 0 ]]
	then
		TIMESTAMP_LAST_DETECTED=$SENSOR_LAST_DETECTED;
		log_time $TIMESTAMP_LAST_DETECTED
	fi
	
	#Si le détecteur est reachable ainsi que la lumière : TODO

	difference_seconds=$(($SENSOR_LAST_DETECTED-$TIMESTAMP_LAST_DETECTED))
	test $conf_debug -eq 1 && echo "Time since last detection : "$difference_seconds" seconds"

	if [[ $difference_seconds -gt $conf_seconds_between_detection ]]
	then
		test $conf_debug -eq 1 && echo "Now detected : "$SENSOR_LAST_DETECTED
		TIMESTAMP_LAST_DETECTED=$SENSOR_LAST_DETECTED
		#Send_state
		log_time $TIMESTAMP_LAST_DETECTED
	fi

done
