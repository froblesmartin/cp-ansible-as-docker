FROM redhat/ubi10

# A stand-in for a managed node: systemd as PID 1 plus sshd, which is how
# cp-ansible's own molecule scenarios test against containers. systemd is
# needed because every CP component is installed as a unit.
RUN dnf -y --disableplugin=subscription-manager install \
    systemd \
    openssh-server \
    openssh-clients \
    sudo \
    openssl \
    unzip \
    rsync \
    procps-ng \
    iproute \
    java-25-openjdk \
    && dnf clean all && rm -rf /var/cache/dnf

RUN rm -f /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/anaconda.target.wants/* \
    && systemctl enable sshd

# Password auth as well as the key, so the test can prove the control node's
# source-built sshpass works.
RUN useradd --create-home --shell /bin/bash ansible \
    && echo 'ansible:ansible' | chpasswd \
    && chmod 0644 /etc/shadow \
    && echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible \
    && install -d -o ansible -g ansible -m 0700 /home/ansible/.ssh

COPY node-init.sh /usr/local/bin/node-init.sh

VOLUME ["/sys/fs/cgroup"]
CMD ["/usr/local/bin/node-init.sh"]
