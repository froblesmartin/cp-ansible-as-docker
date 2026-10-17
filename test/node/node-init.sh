#!/bin/bash
# Pick up the throwaway key the keygen service put in the shared volume, then
# hand PID 1 over to systemd.
set -eu

if [ -f /keys/id_ed25519.pub ]; then
    install -o ansible -g ansible -m 0600 \
        /keys/id_ed25519.pub /home/ansible/.ssh/authorized_keys
fi

exec /usr/lib/systemd/systemd
