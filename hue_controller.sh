#!/bin/bash

##### VARIABLES ######
CONFIG_FILE="hue_controller.yml"
PARAMETERS=( conf_huebridge_ip conf_sensor_name conf_light_name conf_debug )

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


echo "Hue controller @MNE_v0.1 : August 2018"

echo "Lecture du fichier de configuration : $CONFIG_FILE"
eval $(parse_yaml $CONFIG_FILE "conf_")
echo "Vérification des paramètres"
for param in "${PARAMETERS[@]}"
do
	verify_param $param;
done

