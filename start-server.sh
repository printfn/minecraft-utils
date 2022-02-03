#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" == 0 ]]; then
    echo "Usage: $0 <public ip>" >&2
    exit 1
fi

SERVER_IP="$1"
REGION="us-east-1"

curl -s --fail-with-body -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" | jq .

ZONE_ID=$(curl -s --fail-with-body -X GET \
    "https://api.cloudflare.com/client/v4/zones?name=flry.net" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

RECORD_ID=$(curl -s --fail-with-body -X GET \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=mc.flry.net" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

curl -s --fail-with-body -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"$SERVER_IP\",\"ttl\":60,\"proxied\":false}" | jq .

ssh -i ~/.ssh/$REGION.pem \
    -o "UserKnownHostsFile=/dev/null" \
    -o "StrictHostKeyChecking=accept-new" \
    ec2-user@mc.flry.net "

    aws configure set aws_access_key_id $(aws configure get aws_access_key_id --profile terraform)
    aws configure set aws_secret_access_key $(aws configure get aws_secret_access_key --profile terraform)
    sudo yum update -y
    sudo rpm --import https://yum.corretto.aws/corretto.key
    sudo curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
    sudo yum install -y jq java-17-amazon-corretto-devel
    java -version
    LATEST_SNAPSHOT=\$(bash <(curl --proto '=https' --tlsv1.2 -sSf \\
        https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) list-latest-snapshot)
    bash <(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) \$LATEST_SNAPSHOT
    PREV_BACKUP=\$(aws s3api list-objects-v2 --bucket printfn-data --prefix minecraft-sophie-backups/|jq -r '.Contents[-1].Key')
    PREV_BACKUP_FILE=\$(echo \$PREV_BACKUP|sed s,minecraft-sophie-backups/,,)
    aws s3 cp \"s3://printfn-data/\$PREV_BACKUP\" \"\$PREV_BACKUP_FILE\"
    tar -xf \"\$PREV_BACKUP_FILE\"
    java -jar server.jar

    printf \"Create backup? \"
    read -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        NEW_BACKUP_FILE=\"minecraft-\$(TZ=Pacific/Auckland date '+%Y-%m-%d')-\$LATEST_SNAPSHOT.tar.bz2\"
        sudo tar -cvjSf \$NEW_BACKUP_FILE banned-ips.json banned-players.json eula.txt logs ops.json server.properties usercache.json whitelist.json world
        aws s3 cp --storage-class STANDARD_IA \$NEW_BACKUP_FILE s3://printfn-data/minecraft-sophie-backups/
    fi
"

echo "You can connect to the server manually with:"
echo "ssh -i ~/.ssh/$REGION.pem -o \"UserKnownHostsFile=/dev/null\" -o \"StrictHostKeyChecking=accept-new\" ec2-user@mc.flry.net"
