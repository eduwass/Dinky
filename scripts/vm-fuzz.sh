#!/usr/bin/env bash
# Copies the debug binary and fuzz.py into the Tart VM `dinky`, restarts the app there from that binary,
# runs the fuzzer over ssh and prints its output. Usage: scripts/vm-fuzz.sh <seed> <steps>
set -uo pipefail
cd "$(dirname "$0")/.."

IP="${DINKY_VM_IP:-$(tart ip dinky)}"
SSH_OPTS=(-i ~/.ssh/id_rsa -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/dinky-known-hosts)

ssh "${SSH_OPTS[@]}" "admin@$IP" 'pkill -f "[d]inky.app"; pkill -f "[d]inky[-a-z0-9]* app"; pkill -x TextEdit; pkill -x Safari; sleep 1'
scp -q "${SSH_OPTS[@]}" .build/debug/dinky "admin@$IP:dinky-fuzz"
scp -q "${SSH_OPTS[@]}" scripts/fuzz.py "admin@$IP:fuzz.py"
ssh "${SSH_OPTS[@]}" "admin@$IP" 'nohup ~/dinky-fuzz app > /tmp/dinky-fuzz.log 2>&1 < /dev/null & sleep 3'
ssh "${SSH_OPTS[@]}" "admin@$IP" "python3 -u ~/fuzz.py --seed $1 --steps $2 --dinky ~/dinky-fuzz"
status=$?
ssh "${SSH_OPTS[@]}" "admin@$IP" 'pkill -f "[d]inky-fuzz app"; echo "app log: /tmp/dinky-fuzz.log in the guest"'
exit $status
