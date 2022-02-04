#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" == 0 ]]; then
    echo "Usage: $0 <region>" >&2
    exit 1
fi

REGION="$1"

confirm() {
    echo "$1"
    read -r -p "Press enter to confirm, or Ctrl-C to cancel"
    echo
}

echo "Checking if a 'Minecraft' security group exists..."
SG_INFO="$(aws --region $REGION ec2 describe-security-groups \
    --filters "Name=group-name,Values=Minecraft" | jq ".SecurityGroups")"

if [[ "$(echo $SG_INFO | jq length)" == "1" ]]; then
    SG_ID=$(echo $SG_INFO | jq -r ".[0].GroupId")
    VPC_ID=$(echo $SG_INFO | jq -r ".[0].VpcId")
    echo "Found security group $SG_ID in VPC $VPC_ID"
else
    echo "Not found"
    echo "Finding default VPC..."
    VPC_INFO="$(aws --region $REGION ec2 describe-vpcs --filters "Name=is-default,Values=true")"
    if [[ "$(echo $VPC_INFO | jq ".Vpcs | length")" == "1" ]]; then
        VPC_ID=$(echo "$VPC_INFO" | jq -r ".Vpcs[0].VpcId")
        echo "Found default VPC: $VPC_ID"
    else
        echo "Could not find a default VPC, aborting"
        exit 1
    fi

    echo "Creating 'Minecraft' security group..."
    SG_ID="$(aws --region $REGION ec2 create-security-group \
        --group-name Minecraft \
        --description "Minecraft Server (and SSH access)" \
        --vpc-id "$VPC_ID" | jq -r .GroupId)"

    echo "Enabling SSH access..."
    aws --region $REGION ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 >/dev/null

    echo "Enabling Minecraft access..."
    aws --region $REGION ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 25565 \
        --cidr 0.0.0.0/0 >/dev/null

    echo "Successfully created 'Minecraft' security group: $SG_ID"
fi

# List Linux AMIs:
# aws ssm get-parameters-by-path --path /aws/service/ami-amazon-linux-latest --query "Parameters[].Name"

echo "Launching server..."
EC2_INFO=$(aws --region $REGION ec2 run-instances \
    --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-arm64-gp2 \
    --instance-type t4g.medium \
    --key-name $REGION \
    --security-group-ids "$SG_ID" \
    --associate-public-ip-address)

EC2_ID=$(echo $EC2_INFO | jq -r ".Instances[0].InstanceId")

echo "Waiting for server to come online..."
aws --region $REGION ec2 wait instance-running --instance-ids $EC2_ID

echo "Retrieving IP address..."
SERVER_IP=$(aws --region $REGION ec2 describe-instances --instance-ids $EC2_ID \
    | jq -r ".Reservations[0].Instances[0].PublicIpAddress")

echo "Launched server $EC2_ID (IP: $SERVER_IP)"

echo "You can manually connect to the server with:"
echo "ssh -i ~/.ssh/$REGION.pem -o \"UserKnownHostsFile=/dev/null\" -o \"StrictHostKeyChecking=accept-new\" -o \"LogLevel=ERROR\" ec2-user@$SERVER_IP"
echo

echo "Checking if Cloudflare API token is valid..."
curl -s --fail-with-body -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" >/dev/null

echo "Finding Cloudflare Zone ID..."
ZONE_ID=$(curl -s --fail-with-body -X GET \
    "https://api.cloudflare.com/client/v4/zones?name=flry.net" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

echo "Finding Cloudflare DNS Record Id..."
RECORD_ID=$(curl -s --fail-with-body -X GET \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=mc.flry.net" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

echo "Setting Cloudflare DNS A record to $SERVER_IP..."
curl -s --fail-with-body -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
    -H "Authorization: Bearer $(cat ~/.cloudflare/minecraft-token)" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"$SERVER_IP\",\"ttl\":60,\"proxied\":false}" >/dev/null

echo "Connecting to server..."
ssh -i ~/.ssh/$REGION.pem \
    -o "UserKnownHostsFile=/dev/null" \
    -o "StrictHostKeyChecking=accept-new" \
    -o "LogLevel=ERROR" \
    ec2-user@$SERVER_IP "

    echo \"Successfully connected to server\"
    aws configure set aws_access_key_id $(aws configure get aws_access_key_id --profile default)
    aws configure set aws_secret_access_key $(aws configure get aws_secret_access_key --profile default)
    echo \"Updating packages...\"
    sudo yum update -y >/dev/null
    echo \"Installing packages...\"
    sudo rpm --import https://yum.corretto.aws/corretto.key
    sudo curl -sL -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
    sudo yum install -y jq java-17-amazon-corretto-devel >/dev/null
    echo \"Successfully installed Java 17\":
    java -version
    echo \"Finding latest snapshot...\"
    LATEST_SNAPSHOT=\$(bash <(curl --proto '=https' --tlsv1.2 -sSf \\
        https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) list-latest-snapshot)
    bash <(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) \$LATEST_SNAPSHOT
    PREV_BACKUP=\$(aws s3api list-objects-v2 --bucket printfn-data --prefix minecraft-sophie-backups/|jq -r '.Contents[-1].Key')
    PREV_BACKUP_FILE=\$(echo \$PREV_BACKUP|sed s,minecraft-sophie-backups/,,)
    echo \"Downloading last backup...\"
    aws s3 cp --quiet \"s3://printfn-data/\$PREV_BACKUP\" \"\$PREV_BACKUP_FILE\"
    echo \"Extracting last backup...\"
    tar -xf \"\$PREV_BACKUP_FILE\"
    java -jar server.jar

    printf \"Create backup? \"
    read -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        NEW_BACKUP_FILE=\"minecraft-\$(TZ=Pacific/Auckland date "+%Y-%m-%d")-\$LATEST_SNAPSHOT.tar.bz2\"
        sudo tar -cvjSf \$NEW_BACKUP_FILE \\
            banned-ips.json banned-players.json eula.txt logs \\
            ops.json server.properties usercache.json whitelist.json \\
            world >/dev/null
        aws s3 cp --quiet --storage-class STANDARD_IA \\
            \$NEW_BACKUP_FILE s3://printfn-data/minecraft-sophie-backups/
    fi
"

confirm "Shut down server?"

echo "Terminating server..."
aws --region $REGION ec2 terminate-instances --instance-ids $EC2_ID >/dev/null
aws --region $REGION ec2 wait instance-terminated --instance-ids $EC2_ID

echo "Deleting security group..."
aws --region $REGION ec2 delete-security-group --group-id $SG_ID
