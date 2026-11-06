#!/usr/bin/env bash
# down.sh: tear down everything up.sh recorded in .state, in reverse order.
# Safe to re-run: each step skips what isn't there and keeps going on errors.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/config.sh"
STATE=$HERE/.state
[[ -e $STATE ]] || { echo "no $STATE: nothing to tear down"; exit 0; }
source "$STATE"
aws() { command aws --region "$REGION" --output text "$@"; }
say() { printf '\e[1;36m==> %s\e[0m\n' "$*"; }
retry() { for _ in $(seq 20); do "$@" 2>/dev/null && return 0; sleep 6; done; "$@"; }
FAILED=0
try() { "$@" || { echo "    (failed: $*)"; FAILED=1; }; }

if [[ -n ${DNS_SET:-} ]]; then
  say "Deleting $HOST -> $IP"
  try aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --query ChangeInfo.Id --change-batch \
    "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"$HOST\",\"Type\":\"A\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"$IP\"}]}}]}"
fi
if [[ -n ${INSTANCE_ID:-} ]]; then
  say "Terminating $INSTANCE_ID"
  try aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --query 'TerminatingInstances[0].CurrentState.Name'
  try aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
fi
# ENIs can take a moment to let go after termination, hence retry.
[[ -n ${SG_ID:-} ]] && { say "Deleting security group"; try retry aws ec2 delete-security-group --group-id "$SG_ID"; }
[[ -n ${SUBNET_ID:-} ]] && { say "Deleting subnet"; try retry aws ec2 delete-subnet --subnet-id "$SUBNET_ID"; }
[[ -n ${RTB_ID:-} ]] && { say "Deleting route table"; try retry aws ec2 delete-route-table --route-table-id "$RTB_ID"; }
if [[ -n ${IGW_ID:-} ]]; then
  say "Deleting internet gateway"
  [[ -n ${VPC_ID:-} ]] && try retry aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  try retry aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
fi
[[ -n ${VPC_ID:-} ]] && { say "Deleting VPC"; try retry aws ec2 delete-vpc --vpc-id "$VPC_ID"; }

if (( FAILED )); then
  echo "Some steps failed; keeping $STATE so you can re-run ./down.sh."
  exit 1
fi
rm -f "$STATE" "$HERE/.user-data" "$HERE/.known_hosts"
ssh-keygen -R "$HOST" >/dev/null 2>&1 || true; ssh-keygen -R "[$HOST]:443" >/dev/null 2>&1 || true
say "All gone. Leftover check:"
aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$NAME" --query 'Vpcs[].VpcId'
echo "(blank lines above = nothing left)"
