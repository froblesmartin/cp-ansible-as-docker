# cp-ansible as Docker

A Docker image that packages [cp-ansible](https://github.com/confluentinc/cp-ansible)
as a ready-to-use Ansible control node for Confluent Platform 8.3.1. It is built
on `redhat/ubi10` and pins Python to 3.12 (`PYTHON_VERSION`).

## Published images

Every push to a version branch (`8.3`, `7.9`, ...) publishes a `linux/amd64`
image to both registries:

```shell
docker pull ghcr.io/froblesmartin/cp-ansible-as-docker:8.3.1
docker pull froblesmartin/cp-ansible:8.3.1
```

Tags are the full and the `major.minor` CP version, read from the Dockerfile's
`CP_VERSION`, plus `sha-<commit>`. `latest` is applied only by a manual run of
the workflow with **Also tag as latest** ticked.

The published image carries no Confluent Platform artifacts. Bundling them is
a build-time option you run yourself -- see
[Air-gapped installs](#air-gapped-installs).

Docker Hub needs the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository
secrets; without them the workflow publishes to GHCR alone and warns. Set the
`DOCKERHUB_REPOSITORY` variable to push somewhere other than
`froblesmartin/cp-ansible`.

## Usage

Or build it yourself:

```shell
docker build -t cp-ansible:8.3.1 .
```

Check connectivity with the hosts:

```shell
docker run -v ./cp:/data -it cp-ansible:8.3.1 ansible -i /data/hosts.yml -m ping all
```

Run cp-ansible:

```shell
docker run -v ./cp:/data -it cp-ansible:8.3.1 ansible-playbook -i /data/hosts.yml confluent.platform.all
```

## Ansible configuration

The image sets no `ANSIBLE_*` variables, so configuration is yours to supply.
Copy this repository's `ansible.cfg` to your inventory directory and mount it
-- it mirrors the one cp-ansible ships upstream (`hash_behaviour=merge`,
`profile_tasks`, pipelining):

```shell
docker run -v ./cp:/data -e ANSIBLE_CONFIG=/data/ansible.cfg -it \
  cp-ansible:8.3.1 ansible-playbook -i /data/hosts.yml confluent.platform.all
```

`ANSIBLE_CONFIG` is needed because Ansible only auto-discovers an
`ansible.cfg` in the working directory, which is `/home/ansible`, not the
mount point. Check what took effect with:

```shell
docker run -v ./cp:/data -e ANSIBLE_CONFIG=/data/ansible.cfg -it \
  cp-ansible:8.3.1 ansible-config dump --only-changed -t all
```

`-t all` matters: without it the dump omits connection-plugin settings such as
`pipelining` and `timeout`.

Note that `ANSIBLE_*` environment variables outrank every config file, which
is why they are not baked into the image -- they would make a mounted
`ansible.cfg` silently ineffective. For the same reason, do not set
`collections_path` in your config: the collections live in
`/usr/share/ansible/collections` and overriding the path would hide them.

## SSH host key verification

The image ships `/etc/ssh/ssh_config.d/99-cp-ansible.conf` with
`StrictHostKeyChecking accept-new`: an unknown host key is recorded and
accepted, a key that has *changed* is refused. That only protects you if the
record survives, and the container is ephemeral -- so mount a `known_hosts`
next to the inventory, where it belongs:

```shell
touch ./cp/known_hosts
docker run -v ./cp:/data -v ./cp/known_hosts:/home/ansible/.ssh/known_hosts \
  -e ANSIBLE_CONFIG=/data/ansible.cfg -it \
  cp-ansible:8.3.1 ansible-playbook -i /data/hosts.yml confluent.platform.all
```

Create the file on the host first -- Docker creates a *directory* for a bind
mount whose source is missing -- and make it writable by uid 1001 so
`accept-new` can append to it.

Without that mount, every run is a first run, and a host that has been
replaced or impersonated is accepted in silence. Verify this for yourself with
`ssh -G anyhost` inside the container; it prints the settings actually in
effect.

For a stronger guarantee, pre-populate `known_hosts` from a channel you trust
(cloud console output, Terraform, the customer's CMDB) and mount your own
config over the shipped one to refuse anything unknown:

```
Host *
   StrictHostKeyChecking yes
   UserKnownHostsFile ~/.ssh/known_hosts
```

```shell
docker run -v ./cp:/data -v ./cp/known_hosts:/home/ansible/.ssh/known_hosts \
  -v ./cp/ssh_config:/etc/ssh/ssh_config.d/99-cp-ansible.conf:ro \
  -e ANSIBLE_CONFIG=/data/ansible.cfg -it \
  cp-ansible:8.3.1 ansible-playbook -i /data/hosts.yml confluent.platform.all
```

`ssh-keyscan -H -f hosts.txt >> known_hosts` is the pragmatic way to seed the
file, but be clear about what it buys: it trusts whatever answers *at that
moment*. It collapses the exposure from every run to one, and leaves you a
file you can diff and review.

If the customer runs an SSH certificate authority (Vault, Teleport, step-ca),
a single `@cert-authority * <ca-pubkey>` line in `known_hosts` verifies the
whole fleet and needs no update when brokers are added.

Whatever you choose, do **not** set `host_key_checking=False` in
`ansible.cfg`. Ansible does not merely defer to `ssh_config` -- it injects
`-o StrictHostKeyChecking=no` on the command line, which outranks every config
file and silently undoes all of the above. A cp-ansible run is a poor one to
hand to the wrong host: `sshpass` is installed for password auth, pipelining
puts module arguments on stdin, and the `ssl` role distributes keystores,
truststores and their passwords alongside SASL, MDS and LDAP credentials.

## Running rootless

The container runs as the unprivileged user `ansible` (uid 1001), not root.
Mounted inventories and SSH keys therefore have to be readable by uid 1001.
If your host uid differs, build the image to match it instead of passing
`docker run -u` -- an arbitrary uid has no `/etc/passwd` entry, and OpenSSH
refuses to start without one ("No user exists for uid N"):

```shell
docker build --build-arg ANSIBLE_UID=$(id -u) -t cp-ansible:8.3.1 .
```

The image also runs unchanged under a rootless runtime, where container uid 0
is already mapped to your unprivileged host user.

## Air-gapped installs

### Bundling the artifacts

Bundle the Confluent Platform archive and the other install artifacts into the
image. Off by default, since it adds ~2.5 GB:

```shell
docker build --build-arg INCLUDE_ARTIFACTS=true -t cp-ansible:8.3.1 .
```

This variant is deliberately **not published**. Confluent Platform is not
freely redistributable -- Control Center and other components are covered by
the Confluent Enterprise licence -- so pushing an image containing them to a
public registry would be redistribution. Build it yourself, under your own
entitlement, and keep it in your own registry.

They land in `/opt/confluent-artifacts`, also exported as `$CP_ARTIFACTS_DIR`:

```
confluent-8.3.1.tar.gz                           CP archive
confluent-control-center-next-gen-2.6.1.tar.gz   Control Center Next Gen
jolokia-jvm-1.6.2-agent.jar                      Jolokia JVM agent
jmx_prometheus_javaagent-1.0.1.jar               Prometheus JMX exporter
confluent_4.73.0_linux_amd64.tar.gz              Confluent CLI
confluent-usm-agent-1.2.0-amd64.tar.gz           USM agent (only with a usm_agent group)
python-wheels/                                   Python deps for the managed nodes
```

### Pointing the inventory at them

The `*_remote: false` flags are the important part: they mean "this path is on
the Ansible control node" -- i.e. inside this container -- so Ansible copies
the file out to every managed node over SSH. Leave them at the default `true`
when the nodes can reach the URLs themselves.

```yaml
all:
  vars:
    installation_method: archive
    confluent_archive_file_source: /opt/confluent-artifacts/confluent-8.3.1.tar.gz
    confluent_archive_file_remote: false

    jolokia_enabled: true
    jolokia_jar_url: /opt/confluent-artifacts/jolokia-jvm-1.6.2-agent.jar
    jolokia_url_remote: false

    jmxexporter_enabled: true
    jmxexporter_jar_url: /opt/confluent-artifacts/jmx_prometheus_javaagent-1.0.1.jar
    jmxexporter_url_remote: false

    confluent_cli_archive_file_source: /opt/confluent-artifacts/confluent_4.73.0_linux_amd64.tar.gz
    confluent_cli_archive_file_remote: false

    # 8.3.1 defaults this to 2.2.0; it has to match the bundled tarball, since
    # the version is part of the install directory name
    confluent_control_center_next_gen_package_version: 2.6.1
    confluent_archive_control_center_next_gen_file_source: /opt/confluent-artifacts/confluent-control-center-next-gen-2.6.1.tar.gz
    confluent_archive_control_center_next_gen_file_remote: false

    # only needed when the inventory has a usm_agent group
    confluent_archive_usm_agent_file_source: /opt/confluent-artifacts/confluent-usm-agent-1.2.0-amd64.tar.gz
    confluent_archive_usm_agent_file_remote: false
```

The CLI is the easiest one to miss: it is not part of the CP archive, and
`confluent_cli_download_enabled` defaults to `true`, so without the override
above every managed node tries to reach S3 on its own. Set
`confluent_cli_download_enabled: false` instead if you do not need it.

### Python dependencies on the managed nodes

The wheels have no cp-ansible variable -- they are the interpreter-level deps
the collection's modules import on the managed nodes, so they have to be in
place before the playbook runs:

```shell
ansible all -i /data/hosts.yml -b \
  -m copy -a "src=/opt/confluent-artifacts/python-wheels/ dest=/tmp/python-wheels/"
ansible all -i /data/hosts.yml -b -m shell \
  -a "python3 -m pip install --no-index --find-links /tmp/python-wheels pip packaging cryptography cffi PyYAML setuptools"
```

With those in place, skip the tasks that would otherwise reach PyPI -- the
`pip-package` tag covers cp-ansible's `pip install --upgrade pip` and its
`cryptography` install:

```shell
ansible-playbook -i /data/hosts.yml --skip-tags pip-package confluent.platform.all
```

The wheels are distro-agnostic but tied to the interpreter: `cffi` and
`PyYAML` are `cp312`-tagged, so the managed nodes need Python 3.12. The glibc
floor is 2.17, which RHEL 8 already clears.

## Build arguments

| Purpose                                   | Arguments                                                                                                     |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Internal mirrors                          | `CP_ARTIFACTS_BASEURL`, `MAVEN_BASEURL`, `CONFLUENT_CLI_BASEURL`                                              |
| Track cp-ansible's version defaults       | `JOLOKIA_VERSION`, `JMXEXPORTER_VERSION`, `CONFLUENT_CLI_VERSION`, `C3_NEXT_GEN_VERSION`, `USM_AGENT_VERSION` |
| Managed nodes differing from the defaults | `TARGET_GOARCH`, `TARGET_WHEELS`, `TARGET_WHEEL_PLATFORMS`, `TARGET_PYTHON_VERSION`                           |
| Control node itself                       | `ANSIBLE_UID`, `PYTHON_VERSION`, `JAVA_PACKAGE`, `CP_VERSION`, `SSHPASS_VERSION`                              |

The image ships Java 21 and `openssl` so `keytool` is available for building
the keystores and truststores cp-ansible expects.

## Integration test

`test/` holds a Compose stack that builds the image and uses it for what it is
for: installing Confluent Platform. Two UBI 10 containers run systemd as PID 1
and sshd, which is how cp-ansible's own molecule scenarios stand in for managed
nodes, and the control node drives them over SSH.

```shell
docker compose -f test/compose.yaml run --build --rm control
docker compose -f test/compose.yaml down -v
```

The exit code of the `control` service is the exit code of the test. It covers,
in order:

1. **Image contents** -- `ansible --version`, the `confluent.platform` version,
   PyYAML's C loader, `sshpass`, `keytool`.
2. **Key-based SSH** -- a `ping` against both nodes, and `known_hosts` actually
   gaining entries through `accept-new`.
3. **Password SSH** -- the same `ping` through the source-built `sshpass`.
4. **`confluent.platform.validate_hosts`** -- the collection's own preflight.
5. **`confluent.platform.all`** -- a controller on `node1` and a broker on
   `node2`, Community edition, followed by a produce and consume that asserts
   the message came back.

Community edition keeps the test off anything licensed, `installation_method:
package` exercises the repository path rather than the archive, and
`confluent_cli_download_enabled: false` keeps it off S3. The
[`ansible.cfg`](ansible.cfg) mounted into the control node is the same file the
section above tells you to use, so the shipped configuration is what gets
tested.

`confluent.platform.all` takes about eight minutes, on top of the two image
builds -- the nodes pull CP packages from Confluent's repositories on every
run. cp-ansible asserts 7 GB of memory per host, and a container sees the whole
machine's, so give the Docker VM at least that much or `validate_hosts` will
stop the run before it starts.
