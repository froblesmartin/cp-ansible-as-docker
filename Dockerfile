FROM --platform=linux/amd64 ubuntu:jammy

ARG CP_VERSION=7.6.1
ARG COMMUNITY_CRYPTO=2.20.0
ARG COMMUNITY_GENERAL=8.6.1
ARG ANSIBLE_POSIX=1.5.4
ENV ANSIBLE_HASH_BEHAVIOUR=merge

# Copy Python dependency file inside container, then install dependencies using pip.
COPY requirements.txt .

# Add the ssh config to avoid host authencity checks
COPY ssh-config /root/.ssh/config

RUN apt-get update; \
    apt -y install sshpass; \
    apt-get install -y gcc python3; \
    apt-get install -y python3-pip; \
    apt-get clean all 
 
RUN pip3 install --upgrade pip; \
    pip3 install -r requirements.txt


RUN ansible-galaxy collection install confluent.platform:${CP_VERSION};\
    ansible-galaxy collection install ansible.posix:${ANSIBLE_POSIX}; \
    ansible-galaxy collection install community.crypto:${COMMUNITY_CRYPTO}; \
    ansible-galaxy collection install community.general:${COMMUNITY_GENERAL};