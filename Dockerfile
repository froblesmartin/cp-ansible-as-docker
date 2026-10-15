FROM --platform=linux/amd64 ubuntu:noble

# Each ARG/ENV invalidates the build cache for everything below it, whether or
# not the steps below actually reference it, so both are declared as late as
# their first use allows. Runtime-only settings live at the bottom.

ARG PYTHON_VERSION=3.12
# keytool, for building the keystores/truststores cp-ansible expects. The JRE
# is enough for that and for openssl; swap in openjdk-21-jdk-headless if you
# also need jar/jarsigner, at a cost of ~90 MB.
ARG JAVA_PACKAGE=openjdk-21-jre-headless
RUN apt-get update && apt-get install -y \
    sshpass \
    gcc \
    curl \
    openssl \
    ${JAVA_PACKAGE} \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    && apt-get clean all

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
    update-alternatives --set python3 /usr/bin/python${PYTHON_VERSION}

COPY requirements.txt /tmp/requirements.txt
ENV VIRTUAL_ENV=/opt/ansible
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}
RUN python3 -m venv ${VIRTUAL_ENV} && \
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

# System-wide rather than /root/.ssh/config, so the settings apply to whichever
# uid the container runs as. /etc/ssh/ssh_config already Includes this directory.
COPY ssh-config /etc/ssh/ssh_config.d/99-cp-ansible.conf

# Be safe, don't run as root
ARG ANSIBLE_UID=1001
ENV HOME=/home/ansible
RUN useradd --create-home --home-dir ${HOME} --uid ${ANSIBLE_UID} --shell /bin/bash ansible

USER ansible
WORKDIR ${HOME}
