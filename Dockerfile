FROM --platform=linux/amd64 ubuntu:jammy

ARG CP_VERSION=7.1.11
ARG COMMUNITY_CRYPTO=2.21.1
ARG COMMUNITY_GENERAL=8.6.1
ARG ANSIBLE_POSIX=1.5.4
ENV ANSIBLE_HASH_BEHAVIOUR=merge

# Copy Python dependency file inside container, then install dependencies using pip.
COPY requirements.txt .
COPY community-general-7.5.6.tar.gz .

# Add the ssh config to avoid host authencity checks
COPY ssh-config /root/.ssh/config

RUN apt-get update; \
    apt -y install sshpass; \
    apt-get install -y gcc python2; \
    apt-get install -y python-pip; \
    apt-get clean all

RUN pip2 install --upgrade pip; \
    pip2 install -r requirements.txt


RUN ansible-galaxy collection install confluent.platform:${CP_VERSION};\
    ansible-galaxy collection install ansible.posix:${ANSIBLE_POSIX}; \
    ansible-galaxy collection install community.crypto:${COMMUNITY_CRYPTO};


RUN ansible-galaxy collection install community-general-7.5.6.tar.gz