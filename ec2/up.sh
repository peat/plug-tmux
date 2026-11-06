#!/usr/bin/env bash
# up.sh: create a throwaway VPC + EC2 box for the PLUG talk, point $HOST at it,
# wait for setup to finish, and sync the presentation files.
# Every resource ID is written to .state as soon as it exists, so down.sh can
# clean up after a half-finished run.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/config.sh"
STATE=$HERE/.state
aws() { command aws --region "$REGION" --output text "$@"; }
say() { printf '\e[1;36m==> %s\e[0m\n' "$*"; }
die() { printf '\e[1;31m!!! %s\e[0m\n' "$*" >&2; exit 1; }
save() { echo "$1=$2" >>"$STATE"; printf -v "$1" %s "$2"; }
tag() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$NAME}]"; }

[[ -e $STATE ]] && die "$STATE exists. Is a box already up? Run ./down.sh first."
ssh-keygen -R "$HOST" >/dev/null 2>&1 || true; ssh-keygen -R "[$HOST]:443" >/dev/null 2>&1 || true   # new box = new host key; forget the old one (this machine only)
SELF_KEY=${SELF_KEY:-$HOME/.ssh/id_ed25519.pub}
[[ -s $PRESENTER_KEYS && -s $SELF_KEY ]] || die "need $PRESENTER_KEYS and $SELF_KEY"

say "AWS identity: $(aws sts get-caller-identity --query Arn)"

ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$ZONE" --max-items 1 \
  --query "HostedZones[?Name=='$ZONE.'].Id | [0]")
[[ $ZONE_ID == None ]] && die "no hosted zone for $ZONE"
ZONE_ID=${ZONE_ID#/hostedzone/}
EXISTING=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='$HOST.'].Type")
[[ -n $EXISTING && -z ${FORCE_DNS:-} ]] && die "$HOST already has records ($EXISTING). Set FORCE_DNS=1 to overwrite."

AMI=$(aws ssm get-parameter --query Parameter.Value \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id)
say "Ubuntu 24.04 AMI: $AMI"

: >"$STATE"
save REGION "$REGION"; save ZONE_ID "$ZONE_ID"; save HOST "$HOST"

say "Creating network"
save VPC_ID "$(aws ec2 create-vpc --cidr-block 10.77.0.0/16 --tag-specifications "$(tag vpc)" --query Vpc.VpcId)"
aws ec2 wait vpc-available --vpc-ids "$VPC_ID"
save IGW_ID "$(aws ec2 create-internet-gateway --tag-specifications "$(tag internet-gateway)" --query InternetGateway.InternetGatewayId)"
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"
save SUBNET_ID "$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.77.1.0/24 \
  --availability-zone "${REGION}a" --tag-specifications "$(tag subnet)" --query Subnet.SubnetId)"
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch
save RTB_ID "$(aws ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications "$(tag route-table)" --query RouteTable.RouteTableId)"
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID" >/dev/null
save SG_ID "$(aws ec2 create-security-group --group-name "$NAME" --description "PLUG tmux talk: ssh on 22 and 443" \
  --vpc-id "$VPC_ID" --tag-specifications "$(tag security-group)" --query GroupId)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions \
  'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0}]' \
  'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null

say "Rendering user-data"
KEYS=$(cat "$PRESENTER_KEYS" "$SELF_KEY" | grep -E '^(ssh-|ecdsa-|sk-)' | sort -u)
UD=$(<"$HERE/user-data.sh")
UD=${UD//__PRESENTER_KEYS__/$KEYS}
UD=${UD//__DEMO_PASSWORD__/$DEMO_PASSWORD}
UD=${UD//__TMUX_VERSION__/$TMUX_VERSION}
UD=${UD//__MAX_HOURS__/$MAX_HOURS}
UD=${UD//__GHOSTTY_TERMINFO__/$(<"$HERE/terminfo-ghostty.ti")}
printf '%s\n' "$UD" >"$HERE/.user-data"

say "Launching $INSTANCE_TYPE"
save INSTANCE_ID "$(aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" --security-group-ids "$SG_ID" \
  --user-data "file://$HERE/.user-data" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$DISK_GB,VolumeType=gp3,DeleteOnTermination=true}" \
  --metadata-options HttpTokens=required,HttpPutResponseHopLimit=1 \
  --instance-initiated-shutdown-behavior terminate \
  --tag-specifications "$(tag instance)" --query 'Instances[0].InstanceId')"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
save IP "$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress')"
say "Running at $IP"

say "Pointing $HOST at $IP"
CHANGE=$(aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --query ChangeInfo.Id --change-batch \
  "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$HOST\",\"Type\":\"A\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"$IP\"}]}}]}")
save DNS_SET 1
aws route53 wait resource-record-sets-changed --id "$CHANGE"

say "Waiting for sshd"
SSH=(ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HERE/.known_hosts")
for _ in $(seq 60); do "${SSH[@]}" "presentation@$IP" true 2>/dev/null && break; sleep 5; done
say "Waiting for setup to finish (building tmux takes a few minutes)"
"${SSH[@]}" "presentation@$IP" 'cloud-init status --wait >/dev/null; cloud-init status' || true

"$HERE/sync.sh"

say "Smoke test"
"${SSH[@]}" "presentation@$IP" 'bash -lc "tmux -V; claude --version; systemctl is-active fight; sudo nft list ruleset | grep -c skuid"' || true
for user in demo watch; do for port in 22 443; do   # audience logins must offer password on both ports
  methods=$("${SSH[@]}" -v -o PubkeyAuthentication=no -p "$port" "$user@$IP" true 2>&1 | grep -m1 'can continue' | sed 's/.*continue: //')
  [[ $methods == *password* ]] && echo "$user on port $port: ok ($methods)" || echo "!!! $user on port $port offers only: ${methods:-nothing}"
done; done
cat <<EOF

  presenter:  ssh presentation@$HOST     (key only)
  fight:      ssh demo@$HOST             (password: $DEMO_PASSWORD; also on port 443)
  watch:      ssh watch@$HOST            (same password; read-only view of the deck)
  deck:       ssh presentation@$HOST, then: deck
  setup log:  ssh presentation@$HOST cat /var/log/plug-setup.log
  first time: ssh in, cd ~/plug && claude, then log in and accept the folder trust prompt
  teardown:   $HERE/down.sh

  Your laptop may complain about a changed host key. Fix: ssh-keygen -R $HOST; ssh-keygen -R "[$HOST]:443"
EOF
