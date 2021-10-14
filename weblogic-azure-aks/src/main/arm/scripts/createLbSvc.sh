# Copyright (c) 2021, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

# Description: to create Load Balancer Service for the following targets.
#   * [Optional] admin server default channel
#   * [Optional] admin server T3 channel
#   * [Optional] cluster default channel
#   * [Optional] cluster T3 channel
#
# Special parameter example:
#   * lbSvcValues: [{"colName":"admin-t3","colTarget":"adminServerT3","colPort":"7005"},{"colName":"cluster","colTarget":"cluster1T3","colPort":"8011"}]

echo "Script  ${0} starts"

function generate_admin_lb_definicion() {
  cat <<EOF >${scriptDir}/admin-server-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${adminServerLBSVCName}
  namespace: ${wlsDomainNS}
EOF

  # to create internal load balancer service
  if [[ "${enableInternalLB,,}" == "true" ]]; then
    cat <<EOF >>${scriptDir}/admin-server-lb.yaml
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
EOF
  fi

  cat <<EOF >>${scriptDir}/admin-server-lb.yaml
spec:
  ports:
  - name: default
    port: ${adminLBPort}
    protocol: TCP
    targetPort: ${adminTargetPort}
  selector:
    weblogic.domainUID: ${wlsDomainUID}
    weblogic.serverName: ${adminServerName}
  sessionAffinity: None
  type: LoadBalancer
EOF
}

function generate_admin_t3_lb_definicion() {
  cat <<EOF >${adminServerT3LBDefinitionPath}
apiVersion: v1
kind: Service
metadata:
  name: ${adminServerT3LBSVCName}
  namespace: ${wlsDomainNS}
EOF

  # to create internal load balancer service
  if [[ "${enableInternalLB,,}" == "true" ]]; then
    cat <<EOF >>${adminServerT3LBDefinitionPath}
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
EOF
  fi

  cat <<EOF >>${adminServerT3LBDefinitionPath}
spec:
  ports:
  - name: default
    port: ${adminT3LBPort}
    protocol: TCP
    targetPort: ${adminT3Port}
  selector:
    weblogic.domainUID: ${wlsDomainUID}
    weblogic.serverName: ${adminServerName}
  sessionAffinity: None
  type: LoadBalancer
EOF
}

function generate_cluster_lb_definicion() {
  cat <<EOF >${scriptDir}/cluster-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${clusterLBSVCName}
  namespace: ${wlsDomainNS}
EOF

  # to create internal load balancer service
  if [[ "${enableInternalLB,,}" == "true" ]]; then
    cat <<EOF >>${scriptDir}/cluster-lb.yaml
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
EOF
  fi

  cat <<EOF >>${scriptDir}/cluster-lb.yaml
spec:
  ports:
  - name: default
    port: ${clusterLBPort}
    protocol: TCP
    targetPort: ${clusterTargetPort}
  selector:
    weblogic.domainUID: ${wlsDomainUID}
    weblogic.clusterName: ${clusterName}
  sessionAffinity: None
  type: LoadBalancer
EOF
}

function generate_cluster_t3_lb_definicion() {
  cat <<EOF >${clusterT3LBDefinitionPath}
apiVersion: v1
kind: Service
metadata:
  name: ${clusterT3LBSVCName}
  namespace: ${wlsDomainNS}
EOF

  # to create internal load balancer service
  if [[ "${enableInternalLB,,}" == "true" ]]; then
    cat <<EOF >>${clusterT3LBDefinitionPath}
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
EOF
  fi

  cat <<EOF >>${clusterT3LBDefinitionPath}
spec:
  ports:
  - name: default
    port: ${clusterT3LBPort}
    protocol: TCP
    targetPort: ${clusterT3Port}
  selector:
    weblogic.domainUID: ${wlsDomainUID}
    weblogic.clusterName: ${clusterName}
  sessionAffinity: None
  type: LoadBalancer
EOF
}

function query_admin_target_port() {
  if [[ "${enableCustomSSL,,}" == "true" ]]; then
    adminTargetPort=$(utility_query_service_port ${svcAdminServer} ${wlsDomainNS} 'default-secure')
  else
    adminTargetPort=$(utility_query_service_port ${svcAdminServer} ${wlsDomainNS} 'default')
  fi

  echo "Admin port of ${adminServerName}: ${adminTargetPort}"
}

function query_cluster_target_port() {
  if [[ "${enableCustomSSL,,}" == "true" ]]; then
    clusterTargetPort=$(utility_query_service_port ${svcCluster} ${wlsDomainNS} 'default-secure')
  else
    clusterTargetPort=$(utility_query_service_port ${svcCluster} ${wlsDomainNS} 'default')
  fi

  echo "Cluster port of ${clusterName}: ${clusterTargetPort}"
}

function create_lb_svc_for_admin_server_default_channel() {
  item=$1 # input values

  echo ${item}

  adminServerLBSVCNamePrefix=$(cut -d',' -f1 <<<$item)
  adminServerLBSVCName="${adminServerLBSVCNamePrefix}-svc-lb-admin"
  adminLBPort=$(cut -d',' -f3 <<<$item)

  generate_admin_lb_definicion

  kubectl apply -f ${scriptDir}/admin-server-lb.yaml
  utility_validate_status "create lb service for admin server"
  utility_waitfor_lb_svc_completed ${adminServerLBSVCName} \
    ${wlsDomainNS} \
    ${checkSVCStateMaxAttempt} \
    ${checkSVCInterval}

  adminServerEndpoint=$(kubectl get svc ${adminServerLBSVCName} -n ${wlsDomainNS} \
    -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')

  if [ "${enableCustomDNSAlias,,}" == "true" ]; then
    create_dns_A_record "${adminServerEndpoint%%:*}" ${dnsAdminLabel} ${dnsRGName} ${dnsZoneName}
    adminServerEndpoint="${dnsAdminLabel}.${dnsZoneName}:${adminServerEndpoint#*:}"
  fi

  adminConsoleEndpoint="${adminServerEndpoint}/console"
  adminRemoteEndpoint=${adminServerEndpoint}
}

function create_lb_svc_for_admin_t3_channel() {
  item=$1 # input values

  adminServerT3LBSVCNamePrefix=$(cut -d',' -f1 <<<$item)
  adminServerT3LBSVCName="${adminServerT3LBSVCNamePrefix}-svc-t3-lb-admin"
  adminT3LBPort=$(cut -d',' -f3 <<<$item)

  adminServerT3LBDefinitionPath=${scriptDir}/admin-server-t3-lb.yaml
  generate_admin_t3_lb_definicion

  kubectl apply -f ${adminServerT3LBDefinitionPath}
  utility_validate_status "create lb service for admin server t3 channel"
  utility_waitfor_lb_svc_completed ${adminServerT3LBSVCName} \
    ${wlsDomainNS} \
    ${checkSVCStateMaxAttempt} \
    ${checkSVCInterval}

  adminServerT3Endpoint=$(kubectl get svc ${adminServerT3LBSVCName} -n ${wlsDomainNS} \
    -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')

  if [ "${enableCustomDNSAlias,,}" == "true" ]; then
    create_dns_A_record "${adminServerT3Endpoint%%:*}" "${dnszoneAdminT3ChannelLabel}" ${dnsRGName} ${dnsZoneName}
    adminServerT3Endpoint="${dnszoneAdminT3ChannelLabel}.${dnsZoneName}:${adminServerT3Endpoint#*:}"
  fi
}

function create_lb_svc_for_cluster_default_channel() {
  item=$1 # input values

  clusterLBSVCNamePrefix=$(cut -d',' -f1 <<<$item)
  clusterLBSVCName="${clusterLBSVCNamePrefix}-svc-lb-cluster"
  clusterLBPort=$(cut -d',' -f3 <<<$item)

  generate_cluster_lb_definicion

  kubectl apply -f ${scriptDir}/cluster-lb.yaml
  utility_validate_status "create lb service for cluster"
  utility_waitfor_lb_svc_completed ${clusterLBSVCName} \
    ${wlsDomainNS} \
    ${checkSVCStateMaxAttempt} \
    ${checkSVCInterval}

  clusterEndpoint=$(kubectl get svc ${clusterLBSVCName} -n ${wlsDomainNS} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')

  if [ "${enableCustomDNSAlias,,}" == "true" ]; then
    create_dns_A_record "${clusterEndpoint%%:*}" ${dnsClusterLabel} ${dnsRGName} ${dnsZoneName}
    clusterEndpoint="${dnsClusterLabel}.${dnsZoneName}:${clusterEndpoint#*:}"
  fi
}

function create_lb_svc_for_cluster_t3_channel() {
  item=$1 # input values

  clusterT3LBSVCNamePrefix=$(cut -d',' -f1 <<<$item)
  clusterT3LBSVCName="${clusterT3LBSVCNamePrefix}-svc-lb-cluster"
  clusterT3LBPort=$(cut -d',' -f3 <<<$item)

  clusterT3LBDefinitionPath=${scriptDir}/cluster-t3-lb.yaml
  generate_cluster_t3_lb_definicion

  kubectl apply -f ${clusterT3LBDefinitionPath}
  utility_validate_status "create lb service for cluster t3 channel"
  utility_waitfor_lb_svc_completed ${clusterT3LBSVCName} \
    ${wlsDomainNS} \
    ${checkSVCStateMaxAttempt} \
    ${checkSVCInterval}

  clusterT3Endpoint=$(kubectl get svc ${clusterT3LBSVCName} -n ${wlsDomainNS} \
    -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')

  if [ "${enableCustomDNSAlias,,}" == "true" ]; then
    create_dns_A_record "${clusterT3Endpoint%%:*}" ${dnszoneClusterT3ChannelLabel} ${dnsRGName} ${dnsZoneName}
    clusterT3Endpoint="${dnszoneClusterT3ChannelLabel}.${dnsZoneName}:${clusterT3Endpoint#*:}"
  fi
}

function patch_admin_t3_public_address() {
  # patch admin t3 public address
  if [ "${enableCustomDNSAlias,,}" == "true" ]; then
    adminT3Address="${dnszoneAdminT3ChannelLabel}.${dnsZoneName}"
  else
    adminT3Address=$(kubectl -n ${wlsDomainNS} get svc ${adminServerT3LBSVCName} -o json |
      jq '. | .status.loadBalancer.ingress[0].ip' |
      tr -d "\"")
  fi

  if [ $? == 1 ]; then
    echo_stderr "Failed to query public IP of admin t3 channel."
  fi

  currentDomainConfig=$(echo ${currentDomainConfig} |
    jq \
      --arg match "${constAdminT3AddressEnvName}" \
      --arg replace "${adminT3Address}" \
      '.spec.serverPod.env |= map(if .name==$match then (.value=$replace) else . end)')
}

function patch_cluster_t3_public_address() {
  #patch cluster t3 pubilc address
  if [ "${enableCustomDNSAlias,,}" == "true" ]; then
    clusterT3Adress="${dnszoneClusterT3ChannelLabel}.${dnsZoneName}"
  else
    clusterT3Adress=$(kubectl -n ${wlsDomainNS} get svc ${clusterT3LBSVCName} -o json |
      jq '. | .status.loadBalancer.ingress[0].ip' |
      tr -d "\"")
  fi

  if [ $? == 1 ]; then
    echo_stderr "Failed to query public IP of cluster t3 channel."
  fi

  currentDomainConfig=$(echo ${currentDomainConfig} |
    jq \
      --arg match "${constClusterT3AddressEnvName}" \
      --arg replace "${clusterT3Adress}" \
      '.spec.serverPod.env |= map(if .name==$match then (.value=$replace) else . end)')
}

function rolling_update_with_t3_public_address() {
  timestampBeforePatchingDomain=$(date +%s)
  currentDomainConfig=$(kubectl -n ${wlsDomainNS} get domain ${wlsDomainUID} -o json)
  cat <<EOF >${scriptDir}/domainPreviousConfiguration.yaml
${currentDomainConfig}
EOF

  # update public address of t3 channel
  if [[ "${enableAdminT3Channel,,}" == "true" ]]; then
    patch_admin_t3_public_address
  fi

  if [[ "${enableClusterT3Channel,,}" == "true" ]]; then
    patch_cluster_t3_public_address
  fi

  if [[ "${enableClusterT3Channel,,}" == "true" ]] || [[ "${enableAdminT3Channel,,}" == "true" ]]; then
    # restart cluster
    restartVersion=$(kubectl -n ${wlsDomainNS} get domain ${wlsDomainUID} -o json |
      jq '. | .spec.restartVersion' |
      tr -d "\"")
    restartVersion=$((restartVersion + 1))

    currentDomainConfig=$(echo ${currentDomainConfig} |
      jq \
        --arg version "${restartVersion}" \
        '.spec.restartVersion |= $version')

    echo "rolling restart the cluster with t3 public address."
    # echo the configuration for debugging
    cat <<EOF >${scriptDir}/domainNewConfiguration.yaml
${currentDomainConfig}
EOF
    echo ${currentDomainConfig} | kubectl -n ${wlsDomainNS} apply -f -

    replicas=$(kubectl -n ${wlsDomainNS} get domain ${wlsDomainUID} -o json |
      jq '. | .spec.clusters[] | .replicas')

    # wait for the restart completed.
    utility_wait_for_pod_restarted \
      ${timestampBeforePatchingDomain} \
      ${replicas} \
      ${wlsDomainUID} \
      ${checkPodStatusMaxAttemps} \
      ${checkPodStatusInterval}

    utility_wait_for_pod_completed \
      ${replicas} \
      ${wlsDomainNS} \
      ${checkPodStatusMaxAttemps} \
      ${checkPodStatusInterval}
  fi
}

function validate_admin_console_url() {
  local podName=$(kubectl -n ${wlsDomainNS} get pod -l weblogic.serverName=${constAdminServerName} -o json |
    jq '.items[0] | .metadata.name' |
    tr -d "\"")

  if [[ "${podName}" == "null" ]]; then
    echo "Ensure your domain has at least one admin server."
    exit 1
  fi

  adminTargetPort=$(kubectl get svc ${svcAdminServer} -n ${wlsDomainNS} -o json |
    jq '.spec.ports[] | select(.name=="default") | .port')
  local adminConsoleUrl="http://${svcAdminServer}.${wlsDomainNS}:${adminTargetPort}/console/"

  kubectl exec -it ${podName} -n ${wlsDomainNS} -c ${wlsContainerName} \
    -- bash -c 'curl --write-out "%{http_code}\n" --silent --output /dev/null "'${adminConsoleUrl}'" | grep "302"'

  if [ $? == 1 ]; then
    echo "admin console is not accessible."
    # reset admin console endpoint
    adminConsoleEndpoint="null"
  fi
}

#Output value to deployment scripts
function output_result() {
  echo ${adminConsoleEndpoint}
  echo ${clusterEndpoint}
  echo ${adminServerT3Endpoint}
  echo ${clusterT3Endpoint}
  echo ${adminRemoteEndpoint}

  # check if the admin console is accessible, do not output it
  validate_admin_console_url

  result=$(jq -n -c \
    --arg adminEndpoint $adminConsoleEndpoint \
    --arg clusterEndpoint $clusterEndpoint \
    --arg adminT3Endpoint $adminServerT3Endpoint \
    --arg clusterT3Endpoint $clusterT3Endpoint \
    --arg adminRemoteEndpoint ${adminRemoteEndpoint} \
    '{adminConsoleEndpoint: $adminEndpoint, clusterEndpoint: $clusterEndpoint, adminServerT3Endpoint: $adminT3Endpoint, clusterT3Endpoint: $clusterT3Endpoint, adminRemoteEndpoint: $adminRemoteEndpoint}')
  echo "result is: $result"
  echo $result >$AZ_SCRIPTS_OUTPUT_PATH
}

function create_svc_lb() {
  query_admin_target_port
  query_cluster_target_port

  # Parse lb svc input values
  # Generate valid json
  ret=$(echo $lbSvcValues | sed "s/\:/\\\"\:\\\"/g" |
    sed "s/{/{\"/g" |
    sed "s/}/\"}/g" |
    sed "s/,/\",\"/g" |
    sed "s/}\",\"{/},{/g" |
    tr -d \(\))

  cat <<EOF >${scriptDir}/lbConfiguration.json
${ret}
EOF

  array=$(jq -r '.[] | "\(.colName),\(.colTarget),\(.colPort)"' ${scriptDir}/lbConfiguration.json)
  for item in $array; do
    # LB config for admin-server
    target=$(cut -d',' -f2 <<<$item)
    if [[ "${target}" == "adminServer" ]]; then
      create_lb_svc_for_admin_server_default_channel ${item}
    elif [[ "${target}" == "cluster1" ]]; then
      create_lb_svc_for_cluster_default_channel ${item}
    elif [[ "${target}" == "adminServerT3" ]]; then
      echo "query admin t3 port"
      adminT3Port=$(utility_query_service_port ${svcAdminServer} ${wlsDomainNS} 't3channel')
      adminT3sPort=$(utility_query_service_port ${svcAdminServer} ${wlsDomainNS} 't3schannel')

      if [[ "${adminT3Port}" == "null" ]] && [[ "${adminT3sPort}" == "null" ]]; then
        continue
      fi

      if [[ "${adminT3sPort}" != "null" ]]; then
        adminT3Port=${adminT3sPort}
      fi

      create_lb_svc_for_admin_t3_channel $item
      enableAdminT3Channel=true
    elif [[ "${target}" == "cluster1T3" ]]; then
      echo "query cluster t3 port"
      clusterT3Port=$(utility_query_service_port ${svcCluster} ${wlsDomainNS} 't3channel')
      clusterT3sPort=$(utility_query_service_port ${svcCluster} ${wlsDomainNS} 't3schannel')

      if [[ "${clusterT3Port}" == "null" ]] && [[ "${clusterT3sPort}" == "null" ]]; then
        continue
      fi

      if [[ "${clusterT3sPort}" != "null" ]]; then
        clusterT3Port=${clusterT3sPort}
      fi

      create_lb_svc_for_cluster_t3_channel ${item}
      enableClusterT3Channel=true
    fi
  done

  rolling_update_with_t3_public_address
}

# Initialize
script="${BASH_SOURCE[0]}"
scriptDir="$(cd "$(dirname "${script}")" && pwd)"

source ${scriptDir}/common.sh
source ${scriptDir}/utility.sh
source ${scriptDir}/createDnsRecord.sh

enableInternalLB=$1
enableCustomSSL=$2
enableCustomDNSAlias=$3
dnsRGName=$4
dnsZoneName=$5
dnsAdminLabel=$6
dnszoneAdminT3ChannelLabel=$7
dnsClusterLabel=$8
dnszoneClusterT3ChannelLabel=$9
lbSvcValues=${10}
wlsDomainUID=${11}

adminConsoleEndpoint="null"
adminServerName=${constAdminServerName} # define in common.sh
adminServerT3Endpoint="null"
adminRemoteEndpoint="null"
clusterEndpoint="null"
clusterName=${constClusterName}
clusterT3Endpoint="null"
svcAdminServer="${wlsDomainUID}-${adminServerName}"
svcCluster="${wlsDomainUID}-cluster-${clusterName}"
wlsDomainNS="${wlsDomainUID}-ns"

echo ${lbSvcValues}

create_svc_lb

output_result