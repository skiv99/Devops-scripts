#!/bin/bash
### --------------- Парсим yaml файл --------------- ###
parse_yaml () {
   local service_name=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_-]*' fs=$(echo @|tr @ '\034');
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         if (vname[0] == "'$service_name'") {
         printf("%s=\"%s\"\n", $2, $3);
         }
      }
   }'


}
### --------------- Очистка временных переменных --------------- ###
clean () {
unset service_enable
unset imagetag
unset node1
unset node2
unset node3
unset node4
unset preprod
unset port

}
### --------------- Downloading images from the registry --------------- ###
pull_image () {
  echo pull_image
  for service in ${final_deploy_service_list[@]}; do
  clean
  eval $(parse_yaml ./${yaml_file_name} $service)
  echo "!======================= Pulling image ${service}:${imagetag} =======================!"
  docker pull  ${CI_REGISTRY}/${service}:${imagetag}
  if [ $? -eq 0 ]
  then
    echo "Successfully pulling image ${service}:${imagetag}"
  else
    echo -e "\e[1;31mError pulling image ${service}:${imagetag}. Check if the tag is correct\e[0m"
    exit 1
  fi
done

}
### --------------- Get a list of services for deployment --------------- ###
get_service_list () {
  if [  -v deploy_service ]
    then
      #check if all services are specified correctly
      IFS=', ' read -r -a chek_deploy_service_list <<< "$deploy_service"
      grep service ./${yaml_file_name}| sed  's/://' > tmp_service_list
      readarray -t yaml_deploy_service_list < tmp_service_list
      for chek_service in ${chek_deploy_service_list[@]}; do
      find_in_array $chek_service "${yaml_deploy_service_list[@]}"
      done
      get_service_from_varible
    else
      get_service_from_file
  fi
  z=0
  for service in ${deploy_service_list[@]}; do
    clean
    eval $(parse_yaml ./${yaml_file_name} $service)
    if [[ "${service_enable}" != "true" ||  "${!node}" != "true" ]]; then
      echo "Skip deploying: ${service}:${imagetag}"
      unset deploy_service_list[$z]
    fi
    z=$((z+1))
  done

  echo "Service list"
  for service in ${deploy_service_list[@]}; do
    echo $service
  done
  final_deploy_service_list=(${deploy_service_list[@]})
}
### --------------- Check if all services are specified correctly --------------- ###
find_in_array() {
  local key=$1
  shift
  for e in "$@"; do [[ "$e" == "$key" ]] && return 0; done
  echo -e "\e[1;31mService $key not found in service list\e[0m"
  exit 1
}

### --------------- Get the list of services from the yaml file --------------- ###
get_service_from_file () {
  grep service ./${yaml_file_name}| sed  's/://' > tmp_service_list
  readarray -t deploy_service_list < tmp_service_list

  }
### --------------- Get the list of services from the varible --------------- ###
get_service_from_varible () {
IFS=', ' read -r -a deploy_service_list <<< "$deploy_service"
 }
### --------------- Unregister services in eureka --------------- ###
deregistration () {
echo "Unregister services in eureka"
for service in ${final_deploy_service_list[@]}; do
  clean
  eval $(parse_yaml ./${yaml_file_name} $service)
  echo "!======================= Deregistration ${service}:${port} =======================!"
#  port="$(grep SERVER_PORT cicd-scripts/env-file/${environment}/${service} | cut -f2 -d=)"
  curl --connect-timeout 60 --max-time 60 -d "" http://localhost:${port}/v3/internal/deregistration
done
echo "Wait 10 Seconds"
sleep 10s

}

### --------------- Service deploy --------------- ###

deploy () {
  echo "Service deploy"
  for service in ${final_deploy_service_list[@]}; do
  clean
  eval $(parse_yaml ./${yaml_file_name} $service)
    if [[ "${service}" == "service-name-111" ]] && [[ "${ansible_switch}" == "true" ]] ; then
      deploy_gateway
    else
      echo "!======================= Deploying ${service}:${imagetag} =======================!"
      if [[ "${node}" == "preprod" ]] ; then
        docker_run_preprod
      else
        docker_run
      fi
      sleep 20s
    fi
done
  }

deploy_gateway () {
  echo "!======================= Deploying ${service}:${imagetag} =======================!"
  echo "swich node in disable"
  curl -k -i -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${ansible_token}" -d '{"extra_vars":{"nginx_virt_host":"dbo.sovcombank.ru","backend_host":"'${gateway_host}'","method":"deactivate"}}' ${playbook_uri}
  echo "sleep 30s"
  sleep 30s
  docker_run
  echo "sleep 60s"
  sleep 60s
  echo "swich node in enable"
  curl -k -i -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${ansible_token}" -d '{"extra_vars":{"nginx_virt_host":"dbo.sovcombank.ru","backend_host":"'${gateway_host}'","method":"activate"}}' ${playbook_uri}
 }

restart () {
  echo "Restart services"
  for service in ${final_deploy_service_list[@]}; do
  clean
  eval $(parse_yaml ./${yaml_file_name} $service)
    if [[ "${service}" == "service-name-111" ]] && [[ "${node}" != "preprod" ]] ; then
      echo "!======================= Restart ${service} =======================!"
      echo "swich node in disable"
      curl -k -i -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${ansible_token}" -d '{"extra_vars":{"nginx_virt_host":"dbo.sovcombank.ru","backend_host":"'${gateway_host}'","method":"deactivate"}}' ${playbook_uri}
      echo "sleep 30s"
      sleep 30s
      docker restart ${service} || true
      echo "sleep 60s"
      sleep 60s
      echo "swich node in enable"
      curl -k -i -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${ansible_token}" -d '{"extra_vars":{"nginx_virt_host":"dbo.sovcombank.ru","backend_host":"'${gateway_host}'","method":"activate"}}' ${playbook_uri}

    else
      echo "!======================= Restart ${service} =======================!"
      docker restart ${service} || true
    fi
done
}


docker_run () {
  ## stop and run services
  docker stop ${service} || true &&  docker rm -f ${service} || true
  docker run -d --name=${service} \
         --log-driver none \
         --net=host \
         --restart=always \
         -m ${memory_start} \
         --cpus="10" \
         --env-file cicd-scripts/env-file/${environment}/${service} \
         -v /var/log/dbo:/var/log \
         $CI_REGISTRY/${service}:${imagetag}
}

docker_run_preprod () {
  ## stop and run services
  docker stop ${service} || true &&  docker rm -f ${service} || true
  docker run -d --name=${service} \
         --net=host \
         --restart=always \
         -m ${memory_start} \
         --cpus="8" \
         --env-file cicd-scripts/env-file/${environment}/${service} \
         -v /var/log/dbo:/var/log \
         $CI_REGISTRY/${service}:${imagetag}
}

### --------------- Check health services --------------- ###
check_deploy () {
for (( i=1; i <= 18; i++ )) do
  unset service
  echo "!======================= Availability check. TRY №${i} =======================!"
  final_deploy_service_list=(${final_deploy_service_list[@]})
  z=0
  for service in ${final_deploy_service_list[@]}; do
  clean
  eval $(parse_yaml ./${yaml_file_name} $service)
  tmp="$(curl -G --silent --connect-timeout 60 --max-time 60 http://localhost:$port/actuator/health | cut -d \" -f4 )"
  if [[ "$tmp" == "UP" ]]
    then echo -e "\e[1;32mCheck successful: service $service is UP\e[0m"
         unset final_deploy_service_list[$z]
    else echo -e "\e[1;31mCheck fail: service $service is DOWN\e[0m"
  fi
  z=$((z+1))
  done


if [ ${#final_deploy_service_list[@]} -eq 0 ]; then
    break
else
    echo -e "\e[1;31mService not started:\e[0m"
    printf "%s\n" "${final_deploy_service_list[@]}"
fi
sleep 10s
done

if [ ${#final_deploy_service_list[@]} -eq 0 ]; then
    echo -e "\e[1;32m!=======================    All service started     =======================!\e[0m"
    exit 0
else
    echo -e "\e[1;31m!====================== Oops, something went wrong...======================!\e[0m"
    echo  "Service not started:"
    printf "%s\n" "${final_deploy_service_list[@]}"
    exit 1
fi

}


### --------------- start deploy --------------- ###
docker login $CI_REGISTRY -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD"

get_service_list
if [ $1 != restart ];
  then
    pull_image
  fi
deregistration
if [ $1 != restart ];
  then
    deploy
  else
    restart
  fi
check_deploy


docker logout $CI_REGISTRY
