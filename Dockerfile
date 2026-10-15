FROM --platform=linux/amd64 redhat/ubi10

ARG PYTHON_VERSION=3.12
ARG JAVA_PACKAGE=java-21-openjdk-headless
RUN dnf -y --disableplugin=subscription-manager install \
    gcc \
    make \
    openssl \
    openssh-clients \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-pip \
    ${JAVA_PACKAGE} \
    && dnf clean all && rm -rf /var/cache/dnf

# sshpass is in neither the UBI repos nor EPEL 10, so it is built from source.
# Needed only for password authentication; key-based auth never calls it.
ARG SSHPASS_VERSION=1.10
ARG SSHPASS_SHA256=ad1106c203cbb56185ca3bad8c6ccafca3b4064696194da879f81c8d7bdfeeda
RUN curl -fSL --retry 3 --retry-delay 5 -o /tmp/sshpass.tar.gz \
      "https://downloads.sourceforge.net/project/sshpass/sshpass/${SSHPASS_VERSION}/sshpass-${SSHPASS_VERSION}.tar.gz" && \
    echo "${SSHPASS_SHA256}  /tmp/sshpass.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/sshpass.tar.gz -C /tmp && \
    cd /tmp/sshpass-${SSHPASS_VERSION} && \
    ./configure --prefix=/usr/local && make && make install && \
    rm -rf /tmp/sshpass.tar.gz /tmp/sshpass-${SSHPASS_VERSION}

COPY requirements.txt /tmp/requirements.txt
ENV VIRTUAL_ENV=/opt/ansible
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}
RUN python${PYTHON_VERSION} -m venv ${VIRTUAL_ENV} && \
    python3 -m pip install --no-cache-dir --upgrade pip && \
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt

# https://docs.confluent.io/ansible/current/ansible-requirements.html
# https://galaxy.ansible.com/ui/repo/published/confluent/platform/?version=8.3.1
ARG CP_VERSION=8.3.1
# requires_ansible >=2.17 - https://galaxy.ansible.com/ui/repo/published/community/crypto/?version=3.5.0
ARG COMMUNITY_CRYPTO=3.5.0
# requires_ansible >=2.18 - https://galaxy.ansible.com/ui/repo/published/community/general/?version=13.5.0
ARG COMMUNITY_GENERAL=13.5.0
# requires_ansible >=2.16 - https://galaxy.ansible.com/ui/repo/published/ansible/posix/?version=2.2.2
ARG ANSIBLE_POSIX=2.2.2
# requires_ansible >=2.18 - https://galaxy.ansible.com/ui/repo/published/amazon/aws/?version=12.0.0
ARG ANSIBLE_AWS=12.0.0
# Installed system-wide rather than under a home directory so any uid can read them.
ARG COLLECTIONS_DIR=/usr/share/ansible/collections
RUN ansible-galaxy collection install -p ${COLLECTIONS_DIR} confluent.platform:${CP_VERSION} && \
    ansible-galaxy collection install -p ${COLLECTIONS_DIR} ansible.posix:${ANSIBLE_POSIX} && \
    ansible-galaxy collection install -p ${COLLECTIONS_DIR} amazon.aws:${ANSIBLE_AWS} && \
    ansible-galaxy collection install -p ${COLLECTIONS_DIR} community.crypto:${COMMUNITY_CRYPTO} && \
    ansible-galaxy collection install -p ${COLLECTIONS_DIR} community.general:${COMMUNITY_GENERAL} && \
    chmod -R a+rX ${COLLECTIONS_DIR}

# Optionally bundle the install artifacts. Off by default; the CP archive alone
# is ~1.3 GB:
#   docker build --build-arg INCLUDE_ARTIFACTS=true -t cp-ansible:8.3.1 .
ARG INCLUDE_ARTIFACTS=false
ARG CP_ARTIFACTS_BASEURL=https://packages.confluent.io
ARG MAVEN_BASEURL=https://repo1.maven.org/maven2
# Must match cp-ansible's jolokia_version / jmxexporter_version defaults
# https://github.com/confluentinc/cp-ansible/blob/v8.3.1/roles/common/defaults/main.yml#L88
ARG JOLOKIA_VERSION=1.6.2
# https://github.com/confluentinc/cp-ansible/blob/v8.3.1/roles/common/defaults/main.yml#L94
ARG JMXEXPORTER_VERSION=1.0.1
# https://docs.confluent.io/platform/current/installation/versions-interoperability.html#confluent-cli
ARG CONFLUENT_CLI_VERSION=4.73.0
ARG CONFLUENT_CLI_BASEURL=https://s3-us-west-2.amazonaws.com/confluent.cloud
# https://docs.confluent.io/control-center/current/installation/system-requirements.html
ARG C3_NEXT_GEN_VERSION=2.6.1
# https://github.com/confluentinc/cp-ansible/blob/v8.3.1/roles/variables/defaults/main.yml#L3370
ARG USM_AGENT_VERSION=1.2.0
# cp-ansible's confluent_cli_goarch / confluent_usm_agent_goarch value for the
# managed nodes' ansible_architecture (x86_64 -> amd64, aarch64 -> arm64).
ARG TARGET_GOARCH=amd64
# Wheels for the *managed nodes*, not for this control node - the control node's
# own Python deps are in requirements.txt.
ARG TARGET_PYTHON_VERSION=${PYTHON_VERSION}
ARG TARGET_WHEELS="pip packaging cryptography cffi PyYAML setuptools"
ARG TARGET_WHEEL_PLATFORMS="manylinux_2_17_x86_64 manylinux_2_28_x86_64"
ENV CP_ARTIFACTS_DIR=/opt/confluent-artifacts
RUN if [ "${INCLUDE_ARTIFACTS}" = "true" ]; then \
        set -eu; \
        repo_version=$(echo "${CP_VERSION}" | cut -d. -f1,2); \
        py_tag=$(echo "${TARGET_PYTHON_VERSION}" | tr -d .); \
        mkdir -p "${CP_ARTIFACTS_DIR}/python-wheels"; \
        fetch() { echo "fetching $2"; curl -fSL --retry 3 --retry-delay 5 -o "${CP_ARTIFACTS_DIR}/$2" "$1"; }; \
        fetch "${CP_ARTIFACTS_BASEURL}/archive/${repo_version}/confluent-${CP_VERSION}.tar.gz" \
              "confluent-${CP_VERSION}.tar.gz"; \
        fetch "${MAVEN_BASEURL}/org/jolokia/jolokia-jvm/${JOLOKIA_VERSION}/jolokia-jvm-${JOLOKIA_VERSION}-agent.jar" \
              "jolokia-jvm-${JOLOKIA_VERSION}-agent.jar"; \
        fetch "${MAVEN_BASEURL}/io/prometheus/jmx/jmx_prometheus_javaagent/${JMXEXPORTER_VERSION}/jmx_prometheus_javaagent-${JMXEXPORTER_VERSION}.jar" \
              "jmx_prometheus_javaagent-${JMXEXPORTER_VERSION}.jar"; \
        fetch "${CONFLUENT_CLI_BASEURL}/confluent-cli/archives/${CONFLUENT_CLI_VERSION}/confluent_${CONFLUENT_CLI_VERSION}_linux_${TARGET_GOARCH}.tar.gz" \
              "confluent_${CONFLUENT_CLI_VERSION}_linux_${TARGET_GOARCH}.tar.gz"; \
        fetch "${CP_ARTIFACTS_BASEURL}/confluent-usm-agent/archive/confluent-usm-agent-${USM_AGENT_VERSION}-${TARGET_GOARCH}.tar.gz" \
              "confluent-usm-agent-${USM_AGENT_VERSION}-${TARGET_GOARCH}.tar.gz"; \
        fetch "${CP_ARTIFACTS_BASEURL}/confluent-control-center-next-gen/archive/confluent-control-center-next-gen-${C3_NEXT_GEN_VERSION}.tar.gz" \
              "confluent-control-center-next-gen-${C3_NEXT_GEN_VERSION}.tar.gz"; \
        platforms="";for p in ${TARGET_WHEEL_PLATFORMS}; do platforms="${platforms} --platform ${p}"; done; \
        pip download --only-binary=:all: --no-cache-dir \
            --python-version "${py_tag}" --implementation cp --abi "cp${py_tag}" \
            ${platforms} -d "${CP_ARTIFACTS_DIR}/python-wheels" ${TARGET_WHEELS}; \
        chmod -R a+rX "${CP_ARTIFACTS_DIR}"; \
    else \
        echo "INCLUDE_ARTIFACTS=${INCLUDE_ARTIFACTS}: skipping artifact downloads"; \
    fi

COPY ssh-config /etc/ssh/ssh_config.d/99-cp-ansible.conf

# Be safe, don't run as root
ARG ANSIBLE_UID=1001
ENV HOME=/home/ansible
RUN useradd --create-home --home-dir ${HOME} --uid ${ANSIBLE_UID} --shell /bin/bash ansible

USER ansible
WORKDIR ${HOME}
