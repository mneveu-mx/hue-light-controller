#!/bin/bash
set -e
set -u
set -o pipefail
######################
##### VARIABLES ######
CONFIG_FILE="hue_controller.yml"
MANDATORY_PARAMETERS=( conf_huebridge_ip conf_debug conf_hue_api_token conf_store_objects_in_files conf_activate_controller conf_disable_preprocessing )
MANDATORY_CONTROLLER_PARAMETERS=( conf_sensor_name conf_light_name conf_seconds_between_detection conf_create_status_files_only_needed conf_color_day conf_color_night conf_hour_night conf_hour_morning )
PATH_DATAS="datas"
PATH_STORE_LIGHTS=$PATH_DATAS"/lights"
PATH_STORE_SENSORS=$PATH_DATAS"/sensors"
FILE_STORE_HISTORY_DETECTED=$PATH_DATAS"/detected_history.log"
FILE_INDEX_LIGHTS=$PATH_DATAS"/index_lights.mx"
FILE_INDEX_SENSORS=$PATH_DATAS"/index_sensors.mx"
TIMESTAMP_LAST_DETECTED=0
SLEEP_TIME=0.0
##### CONSTANTS ######
ON=1
OFF=0
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

log_debug() {
	test $conf_debug -eq 1 && echo $(date -Ins)" __ DEBUG __ "$@
}

log() {
	echo $(date -Ins)" __ "$@
}

verify_param() {
	[[ -z ${!1} ]] \
		&& log $1 value not present in $CONFIG_FILE, exiting. && exit 1 \
		|| log_debug $1 ":" ${!1};
}

check_params() {
	log "Check parameters on ./"$CONFIG_FILE" file"
	for param in "${MANDATORY_PARAMETERS[@]}"
	do
		verify_param $param;
	done
	if [[ $conf_activate_controller -eq $ON ]]
	then
		for param in "${MANDATORY_CONTROLLER_PARAMETERS[@]}"
		do
			verify_param $param;
		done
	fi
}

check_file_is_updated() {
	nb=$(find datas/ -name $(basename $1) -mmin -$2 | wc -l)
	test $nb -gt 0 || (log "L'index $1 n'est pas à jour" && exit 1)
}

get_index_lights() {
	#curl $HUE_API_URL"/"$1 \
	echo $hue_response \
	| jq -r '.lights | keys[] as $k | "\(.[$k].name)=\($k)"' 1>$1 || (log "L'index $(basename $1) n'a pas été correctement récupéré ou parsé" && exit 1)
	check_file_is_updated $1 2 
}


get_index_sensors() {
	#curl $HUE_API_URL"/"$1 \
	echo $hue_response \
	| jq -r '.sensors | keys[] as $k | "\(.[$k].name)=\($k)"' 1>$1 || (log "L'index $(basename $1) n'a pas été correctement récupéré ou parsé" && exit 1)
	check_file_is_updated $1 2
}

create_status_file() {
	IFS="="
	while read -r k v
	do
		if [ $conf_activate_controller -eq 1 ] && [ $conf_create_status_files_only_needed -eq 1 ]
		then
			if [ $4 = $k ]
			then
				echo $hue_response | jq ".$1.\"$v\"" > $2"/"$k
			fi
		else
			echo $hue_response | jq ".$1.\"$v\"" > $2"/"$k
		fi
	done < $3
	log_debug $(ls $2 | wc -l)" created file(s) for "$1
}

clean_status_files() {
	log_debug "Delete files from "$1"/*"
	rm -rf $1"/*"
}

get_json_value() {
	cat $1 | jq $2
}

get_json_sensor_value() {
	get_json_value $PATH_STORE_SENSORS"/"$conf_sensor_name $1
}

get_json_light_value() {
	get_json_value $PATH_STORE_LIGHTS"/"$conf_light_name $1
}

log_time() {
	echo $(date -d@$1 +"%Y/%m/%d, %H:%M:%S") >> $FILE_STORE_HISTORY_DETECTED
}

enrich_json_with_arg() {
	echo $tmp_json | jq ".$1 += {\"$2\":\"$3\"}"
}

enrich_rgb() {
	#Unable to find a bash script for convert xyz to srgb
	#Maybe TODO
	tmp_json=$(enrich_json_with_arg "state" "srgb" "to_be_done")
}

switch_light() {
	to_string="OFF"
	to_json="false"
	options=""
	if [[ $1 -eq $ON ]]
	then
		to_string="ON";
		to_json="true";
		actual_hour=$(date +%H);
		if [ $actual_hour -lt $conf_hour_morning ] || [ $actual_hour -ge $conf_hour_night ]
		then
			options=$conf_color_night
		else
			options=$conf_color_day
		fi
	fi
	curl -X PUT -H "Content-Type: application/json" -d "{\"on\":$to_json$options}" $HUE_API_URL"lights/"$2"/state" 1>/dev/null
	log_debug "Switch light \""$conf_light_name"\" "$to_string
}

get_hue(){
	hue_response=$(curl $HUE_API_URL -m 2)
}

###############

log "Hue controller @MNE_v0.1 : August 2018"
eval $(parse_yaml $CONFIG_FILE "conf_")
check_params

## Paramètres HUE ##
HUE_API_URL="http://"$conf_huebridge_ip"/api/"$conf_hue_api_token"/"
get_hue
log "Indexes discovery and store on ./"$PATH_DATAS"/*.mx files"
get_index_lights $FILE_INDEX_LIGHTS
get_index_sensors $FILE_INDEX_SENSORS

log_debug $(cat $FILE_INDEX_LIGHTS);
log_debug $(cat $FILE_INDEX_SENSORS);

log "Remove older status files on folders ./"$PATH_STORE_LIGHTS" and ./"$PATH_STORE_SENSORS
clean_status_files $PATH_STORE_LIGHTS
clean_status_files $PATH_STORE_SENSORS

oper_light_index=0
if [[ $conf_activate_controller -eq 1 ]]
then
	temp=$(grep "$conf_light_name" $FILE_INDEX_LIGHTS || (log "\""$conf_light_name"\" does not exist on your hue environment" && exit 1)) 
	oper_light_index=${temp#*=}
	log_debug "\""$conf_light_name"\" is index number "$oper_light_index
	log "\""$conf_light_name"\" will be controlled by \""$conf_sensor_name"\""
else
	log "Controller not activated (cf configuration file)"
fi

tmp_json=""
touch -a $FILE_STORE_HISTORY_DETECTED
while true
do
	sleep $SLEEP_TIME
	#curl
	create_status_file "lights" $PATH_STORE_LIGHTS $FILE_INDEX_LIGHTS $conf_light_name
	create_status_file "sensors" $PATH_STORE_SENSORS $FILE_INDEX_SENSORS $conf_sensor_name
	
	#Enrichissement 
	if [[ $conf_disable_preprocessing -eq 0 ]]
	then
		log "Enrich datas for lights (rgb color)"
		for entry in "$PATH_STORE_LIGHTS"/*
		do
			tmp_json=$(cat $entry)
			enrich_rgb
			echo $tmp_json > "$entry"
		done
		log_debug "End of processing"
	fi
	
	if [[ $conf_activate_controller -eq 1 ]]
	then
		SENSOR_ON=$(get_json_sensor_value ".config.on")
		SENSOR_REACHABLE=$(get_json_sensor_value ".config.reachable")
		SENSOR_LAST_DETECTED_DATE=$(get_json_sensor_value ".state.lastupdated" | tr -d '"')
		SENSOR_LAST_DETECTED=$(date -d$SENSOR_LAST_DETECTED_DATE +%s)
		
		LIGHT_REACHABLE=$(get_json_light_value ".state.reachable")
		LIGHT_ON=$(get_json_light_value ".state.on")
		log_debug "sensor[on]:"$SENSOR_ON
		log_debug "sensor[reachable]:"$SENSOR_REACHABLE
		log_debug "sensor[lastupdated]:"$SENSOR_LAST_DETECTED_DATE"/"$SENSOR_LAST_DETECTED
		log_debug "light[reachable]:"$LIGHT_REACHABLE
		log_debug "light[on]:"$LIGHT_ON
	
		if [[ $TIMESTAMP_LAST_DETECTED -eq 0 ]]
		then
			TIMESTAMP_LAST_DETECTED=$SENSOR_LAST_DETECTED;
			log_time $TIMESTAMP_LAST_DETECTED
		fi
		
		if [ $SENSOR_REACHABLE = "true" ] && [ $LIGHT_REACHABLE = "true" ];
		then
			difference_seconds=$(($SENSOR_LAST_DETECTED-$TIMESTAMP_LAST_DETECTED))
			log_debug "Time since last detection : "$difference_seconds" seconds"
			if [[ $difference_seconds -gt 0 ]]
			then
				#log_debug $SENSOR_LAST_DETECTED
				if [[ $difference_seconds -gt $conf_seconds_between_detection ]]
				then
					log_debug "Now detected : "$SENSOR_LAST_DETECTED
					TIMESTAMP_LAST_DETECTED=$SENSOR_LAST_DETECTED
					if [[ $LIGHT_ON = "true" ]]
					then
						switch_light $OFF $oper_light_index
					else
						switch_light $ON $oper_light_index
					fi
					log_time $TIMESTAMP_LAST_DETECTED
				fi
			fi
		else
			log "Cannot control light because almost one equipment is unreachable, see details below :"
			log "Light is reachable : "$LIGHT_REACHABLE
			log "Sensor is reachable : "$SENSOR_REACHABLE
		fi
	fi

	#It is possible the hue bridge don't answer properly...
	get_hue || hue_response=""
	while [ -z "$(echo "$hue_response" | jq ".lights")" ] && [ -z "$(echo "$hue_response" | jq ".sensors")" ];
	do
		sleep 0.5 && log "Failed to get from hue, retry..."
		get_hue || hue_response=""
	done
done
