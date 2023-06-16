#!/usr/bin/env bashio

declare TOKEN
declare ZONE
declare INTERVAL
declare LOG_PIP
declare DOMAINS
declare PERSISTENT_DOMAINS
declare CHECK_MARK
declare CROSS_MARK

TOKEN=$(bashio::config 'cloudflare_api_token'| xargs echo -n)
ZONE=$(bashio::config 'cloudflare_zone_id'| xargs echo -n)
INTERVAL=$(bashio::config 'interval')
LOG_PIP=$(bashio::config 'log_pip')
PERSISTENT_DOMAINS=$(bashio::config "domains")
#CHECK_MARK="\033[0;32m\xE2\x9C\x94\033[0m"
CROSS_MARK="\u274c"
#BULLET="\u25cf"
BULLET="\u2219"
PLUS="\uff0b"
CHECK_MARK="\u1F5D8"
#PLUS="\u2795"
CLOUD="\U2601"
ITERATION=0
CREATION_ERRORS=0
ITERATION_ERRORS=0
UPDATE_ERRORS=0 
PIP_ERRORS=0


# font
N="\e[0m" #normal
I="\e[3m" #italic
S="\e[9m" #strikethrough
B="\e[1m" #bold

# colors:
RG="\e[0;32m" #regular green
RR="\e[0;31m" #regular red
YY="\e[0;33m" #regular yellow
BL="\e[1;34m" #bold blue
GR="\e[1;32m" #bold green
R="\e[1;31m" #bold red (error)

# checks on configuration
if [[ ${#ZONE} == 0 ]];
then
    echo -e "${RR}Failed to run due to missing Cloudflare Zone ID${N}"
    exit 1
elif [[ ${#TOKEN} == 0 ]];
then
    echo -e "${RR}Failed to run due to missing Cloudflare API token${N}"
    exit 1
fi

function domain_lookup {
  local LIST="$1"
  local ITEM="$2"
  if [[ $LIST =~ (^|[[:space:]])"$ITEM"($|[[:space:]]) ]] ; then return 1; else return 0; fi
}

# Cloudflare API function (get/update/create)
function cfapi {
    ERROR=0
    DOMAIN=$1
    PROXY=true
    if [[ ${DOMAIN} == *"_no_proxy"* ]];
    then
        DOMAIN=$(sed "s/_no_proxy/""/" <<< "$DOMAIN")
        PROXY=false
    fi
    API_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?type=A&name=${DOMAIN}&page=1&per_page=100&match=all" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
        
    if [[ ${API_RESPONSE} == *"\"success\":false"* ]];
    then
        ERROR=$(echo ${API_RESPONSE} | awk '{ sub(/.*"message":"/, ""); sub(/".*/, ""); print }')
        echo -e " ${CROSS_MARK} ${DOMAIN} => ${R}${ERROR}${N}\n"
    fi
    
    if [[ "${API_RESPONSE}" == *'"count":0'* ]];
    then
        ERROR=1
        DATA=$(printf '{"type":"A","name":"%s","content":"%s","ttl":1,"proxied":%s}' "${DOMAIN}" "${PUBLIC_IP}" "${PROXY}")
        API_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            --data ${DATA})

        if [[ ${API_RESPONSE} == *"\"success\":false"* ]];
        then
        
            # creation failed
            CREATION_ERRORS=$(($CREATION_ERRORS + 1))
            ERROR=$(echo ${API_RESPONSE} | awk '{ sub(/.*"message":"/, ""); sub(/".*/, ""); print }')
            echo -e " ${CROSS_MARK} ${DOMAIN} => ${R}${ERROR}${N}"
        else
        
            # creation successful (no need to mention current PIP (again))
            if [[ ${PROXY} == false ]];
            then
                #echo -e " ${GR}${PLUS}${N} ${DOMAIN} (${RR}${I}not proxied${N})"
                echo -e " ${GR}${PLUS}${N} ${DOMAIN} ${CLOUD}"
            else
                echo -e " ${GR}${PLUS}${N} ${DOMAIN}"
                #echo -e " ${GR}${PLUS}${N} ${DOMAIN} (${RG}${I}proxied${N})"
            fi
        fi
    fi
    
    if [[ ${ERROR} == 0 ]];
    then
        DOMAIN_ID=$(echo ${API_RESPONSE} | awk '{ sub(/.*"id":"/, ""); sub(/",.*/, ""); print }')
        DOMAIN_IP=$(echo ${API_RESPONSE} | awk '{ sub(/.*"content":"/, ""); sub(/",.*/, ""); print }')
        DOMAIN_PROXIED=$(echo ${API_RESPONSE} | awk '{ sub(/.*"proxied":/, ""); sub(/,.*/, ""); print }')

        if [[ ${PUBLIC_IP} != ${DOMAIN_IP} ]];
        then
            # difference detected
            DATA=$(printf '{"type":"A","name":"%s","content":"%s","proxied":%s}' "${DOMAIN}" "${PUBLIC_IP}" "${DOMAIN_PROXIED}")
            API_RESPONSE=$(curl -sX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${DOMAIN_ID}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                --data ${DATA})

            if [[ ${API_RESPONSE} == *"\"success\":false"* ]];
            then
            
                # update failed
                UPDATE_ERRORS=$(($UPDATE_ERRORS + 1))
                if [[ ${LOG_PIP} == true ]];
                then
                
                    # show current assigned PIP
                    if [[ ${DOMAIN_PROXIED} == false ]];
                    then
                    
                        #echo -e " ${CROSS_MARK} ${DOMAIN} (${RR}${DOMAIN_IP}${N}) (${RR}${I}not proxied${N}) => ${R}failed to update${N}"
                        echo -e " ${CROSS_MARK} ${DOMAIN} (${RR}${DOMAIN_IP}${N}) ${CLOUD} => ${R}failed to update${N}"
                    else
                        echo -e " ${CROSS_MARK} ${DOMAIN} (${RR}${DOMAIN_IP}${N}) (${RG}${I}proxied${N}) => ${R}failed to update${N}"
                        #echo -e " ${CROSS_MARK} ${DOMAIN} (${RR}${DOMAIN_IP}${N}) (${RG}${I}proxied${N}) => ${R}failed to update${N}"
                    fi
                else
                
                    # don't show current assigned PIP
                    if [[ ${DOMAIN_PROXIED} == false ]];
                    then
                        #echo -e " ${CROSS_MARK} ${DOMAIN} (${RR}${I}not proxied${N}) => ${R}failed to update${N}"
                        echo -e " ${CROSS_MARK} ${DOMAIN} ${CLOUD} => ${R}failed to update${N}"
                    else
                        #echo -e " ${CHECK_MARK} ${DOMAIN} (${RG}${I}proxied${N}) => ${R}failed to update${N}"
                        echo -e " ${CHECK_MARK} ${DOMAIN} => ${R}failed to update${N}"
                    fi
                fi
            else
            
                # update successful
                if [[ ${LOG_PIP} == true ]];
                then
                
                    # show previously assigned PIP
                    if [[ ${DOMAIN_PROXIED} == false ]];
                    then
                        echo -e " ${CHECK_MARK} ${DOMAIN} ${CLOUD} (${YY}${S}${DOMAIN_IP}${N}\e[0m)"
                        #echo -e " ${CHECK_MARK} ${DOMAIN} (${RR}${I}not proxied${N}) (${YY}${S}${DOMAIN_IP}${N}\e[0m)"
                    else
                        #echo -e " ${CHECK_MARK} ${DOMAIN} (${RG}${I}proxied${N}) (${YY}${S}${DOMAIN_IP}${N}\e[0m)"
                        echo -e " ${CHECK_MARK} ${DOMAIN} (${YY}${S}${DOMAIN_IP}${N}\e[0m)"
                    fi
                else
                
                    # don't show previously assigned PIP
                    if [[ ${DOMAIN_PROXIED} == false ]];
                    then
                        echo -e " ${CHECK_MARK} ${DOMAIN} ${CLOUD}"
                        #echo -e " ${CHECK_MARK} ${DOMAIN} (${RR}${I}not proxied${N})"
                    else
                        #echo -e " ${CHECK_MARK} ${DOMAIN} (${RG}${I}proxied${N})"
                        echo -e " ${CHECK_MARK} ${DOMAIN}"
                    fi
                fi
             fi
        else
        
            # nothing changed
            if [[ ${DOMAIN_PROXIED} == false ]];
            then
                echo -e " ${BULLET} ${DOMAIN} ${CLOUD}";
                #echo -e " ${BULLET} ${DOMAIN} (${RR}${I}not proxied${N})";
            else
                #echo -e " ${BULLET} ${DOMAIN} (${RG}${I}proxied${N})";
                echo -e " ${BULLET} ${DOMAIN}";
            fi
        fi
    fi
}

# starting message
if [[ ${INTERVAL} == 1 ]]; then echo -e "${RG}Iterating every minute${N}\n "; else echo -e "${RG}Iterating every ${INTERVAL} minutes${N}\n "; fi

while :
do
    SUCCESS=0
    SECONDS=0
    ISSUE=0
    echo -e "Runtime errors: ${PIP_ERRORS}/${ITERATION_ERRORS}/${CREATION_ERRORS}/${UPDATE_ERRORS}"
    echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    PIP_FETCH_START=`date +%s`
    
    # loop until PIP is known
    while :
    do
    
        # try different APIs to get current PIP
        for i in "api.ipify.org" "api.my-ip.io/ip"
        do PUBLIC_IP=$(curl -s --connect-timeout 5 https://$i || echo 0)
            if [[ $PUBLIC_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
            then
                SUCCESS=1
                break
            fi
        done
        if [[ $SUCCESS == 1 ]]
        then
            break
        fi
        
        # APIs failed to return PIP, retry in 10 seconds
        PIP_ERRORS=$(($PIP_ERRORS + 1))
        echo -e "${RR}Failed to get current public IP address. Retrying in 10 seconds...${N}"
        sleep 10s
    done
    
    # calculate next run time
    PIP_FETCH_TIME=$((`date +%s`-PIP_FETCH_START))
    if [[ ! $PIP_FETCH_TIME -ge $INTERVAL ]]; then PIP_FETCH_TIME=0; fi
    NEXT=$(echo | busybox date -d@"$(( `busybox date +%s`+(${INTERVAL}*60)-$PIP_FETCH_TIME ))" "+%Y-%m-%d %H:%M:%S")
    echo -e "Next: ${NEXT}"

    # print current PIP
    if [[ ${LOG_PIP} == true ]]; then echo -e "PIP: ${BL}${PUBLIC_IP}${N} (${i})"; fi
    
    # fetch existing A records
    DOMAINS=$(curl -sX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?type=A" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[].name')
    
    if [[ ! -z "$DOMAINS" ]];
    then
        count=$(wc -w <<< $PERSISTENT_DOMAINS)
        TMP_PERSISTENT_DOMAINS=$PERSISTENT_DOMAINS
        if [[ $count > 0 ]];
        then
            # add persistent domains to obtained record list
            for DOMAIN in ${TMP_PERSISTENT_DOMAINS[@]};
            do
                TMP_DOMAIN=$(sed "s/_no_proxy/""/" <<< "$DOMAIN")
                #$DOMAINS=( "${DOMAINS[@]/$TMP_DOMAIN}" )
                DOMAINS=( "${DOMAINS[@]/$DOMAIN/}" )
                if `domain_lookup "$DOMAINS" "$TMP_DOMAIN"` ;
                then
                    DOMAINS+=("$DOMAIN")
                fi
                #TMP_PERSISTENT_DOMAINS=( "${TMP_PERSISTENT_DOMAINS[@]/$DOMAIN/}" )
            done
        fi
        
        # sort domain list alphabetically
        DOMAIN_LIST=($(for DOMAIN in "${DOMAINS[@]}"; do echo "${DOMAIN}"; done | sort -u))
        if [[ ! -z "$DOMAIN_LIST" ]];
        then
        
            # iterate through listed domains
            ITERATION=$(($ITERATION + 1))
            if [[ ${#DOMAIN_LIST[@]} == 1 ]]; then DOMAIN_COUNT="${#DOMAIN_LIST[@]} domain"; else DOMAIN_COUNT="${#DOMAIN_LIST[@]} domains"; fi
            echo "Iteration ${ITERATION} (${DOMAIN_COUNT}):"
            for DOMAIN in ${DOMAIN_LIST[@]}; do cfapi ${DOMAIN}; done
        else
        
            # iteration failed
            ITERATION_ERRORS=$(($ITERATION_ERRORS + 1))
            echo -e "${RR}Inner domain list iteration failed. Restarting iteration in 60 seconds...${N}"
            ISSUE=1
        fi
    else
    
        # iteration failed
        ITERATION_ERRORS=$(($ITERATION_ERRORS + 1))
        echo -e "${RR}Outer domain list iteration failed. Restarting iteration in 60 seconds...${N}"
        ISSUE=1
    fi
    
    # set sleep time and wait until next iteration
    if [[ $ISSUE == 1 ]]; then TMP_SEC=60; else TMP_SEC=$(((($INTERVAL*60)-($SECONDS/60))-($SECONDS%60))); fi
    sleep ${TMP_SEC}s
    echo -e "\n "
done
