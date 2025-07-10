#!/usr/bin/env bash


ARCHITECTURE="amd64"
JUJU_VERSION="3.6.5"


function download_juju_agent() {
    # Download the juju agent and store it in the right directory to be picked up on the bootstrap
    LOCAL_JUJU="/home/ubuntu/.local/share/juju"
    JUJU_TOOLS_DIR="${LOCAL_JUJU}/tools"
    JUJU_AGENT_DIR="${JUJU_TOOLS_DIR}/released"
    mkdir -p "${JUJU_AGENT_DIR}"

    juju metadata generate-agent-binaries --stream released

    remote_src="https://streams.canonical.com/juju/tools/agent/${JUJU_VERSION}/juju-${JUJU_VERSION}-linux-${ARCHITECTURE}.tgz"
    local_dest="${JUJU_AGENT_DIR}/juju-${JUJU_VERSION}-ubuntu-${ARCHITECTURE}.tgz"

    curl -L "${remote_src}" -o "${local_dest}"

    chown -R ubuntu:ubuntu "/home/ubuntu/.local"
}


download_juju_agent
