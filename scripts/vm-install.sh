#!/usr/bin/env bash
# Copies build/dinky.app into the Tart VM `dinky` and launches it there.
set -euo pipefail
cd "$(dirname "$0")/.."

IP="$(tart ip dinky)"
SSH_OPTS=(-i ~/.ssh/id_rsa -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/dinky-known-hosts)

ssh "${SSH_OPTS[@]}" "admin@$IP" 'pkill -f dinky.app; mkdir -p ~/Applications && rm -rf ~/Applications/dinky.app'
scp -rq "${SSH_OPTS[@]}" build/dinky.app "admin@$IP:Applications/"
ssh "${SSH_OPTS[@]}" "admin@$IP" 'open ~/Applications/dinky.app'
echo "launched dinky.app in the VM at $IP"
