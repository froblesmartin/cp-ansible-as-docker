#!/bin/bash
# Everything the control node image is supposed to be able to do, in order.
# The exit code of this script is the exit code of the test.
set -euo pipefail

step() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }

# The key lives in a volume shared with the nodes; ssh insists on 0600.
install -m 0600 /keys/id_ed25519 "${HOME}/.ssh/id_ed25519"

step "1/5  Image contents"
ansible --version
ansible-galaxy collection list confluent.platform
python3 -c 'import yaml; assert hasattr(yaml, "CSafeLoader"); print("PyYAML C loader: yes")'
sshpass -V | head -1
keytool -help >/dev/null 2>&1 && echo "keytool: yes"

step "2/5  Key-based connectivity, with accept-new recording the host keys"
# Ansible reports a refused connection as one line of UNREACHABLE, which says
# nothing about why, so get the protocol exchange on the record before giving up.
if ! ansible -i /inventory/hosts.yml -m ping all; then
    printf '\n--- ssh -vvv node1 ---\n'
    ssh -vvv -o BatchMode=yes -o ConnectTimeout=10 \
        -i "${HOME}/.ssh/id_ed25519" ansible@node1 true || true
    exit 1
fi
grep -c . "${HOME}/.ssh/known_hosts" | xargs printf 'host keys recorded: %s\n'

step "3/5  Password authentication through sshpass"
ansible -i /inventory/password-auth.yml -m ping all

step "4/5  confluent.platform.validate_hosts"
ansible-playbook -i /inventory/hosts.yml confluent.platform.validate_hosts

step "5/5  confluent.platform.all, then produce and consume"
ansible-playbook -i /inventory/hosts.yml confluent.platform.all
ansible-playbook -i /inventory/hosts.yml /control/smoke.yml

printf '\n\033[1m=== PASS ===\033[0m\n'
