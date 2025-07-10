#!/usr/bin/env bash


function export_controller_sg_func() {
cat <<'EOF' >> /home/ubuntu/.bash_functions
function apply_security_groups() {
  SG_NAME="juju-controller-sg"

  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

  for instance_id in $(juju show-controller --format yaml | yq '.aws["controller-machines"]' | yq 'to_entries | .[].value."instance-id"' -r); do
    eni_id=$(aws ec2 describe-instances \
      --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
      --output text)

    current_sgs=$(aws ec2 describe-network-interfaces \
      --network-interface-ids "$eni_id" \
      --query 'NetworkInterfaces[0].Groups[*].GroupId' \
      --output text)

    new_sgs=$(echo -e "$current_sgs\n$SG_ID" | sort | uniq | tr '\n' ' ')

    aws ec2 modify-network-interface-attribute \
      --network-interface-id "$eni_id" \
      --groups $new_sgs

    echo "Attached SG $SG_ID to ENI $eni_id (instance $instance_id)"
  done
}
EOF

    echo 'source /home/ubuntu/.bash_functions' >> /home/ubuntu/.bashrc

    chown ubuntu:ubuntu /home/ubuntu/.bash_functions
    chmod 644 /home/ubuntu/.bash_functions

    sudo -u ubuntu bash -l -c "source /home/ubuntu/.bashrc"
}


function setup_ssh() {
    mkdir -p /home/ubuntu/.ssh

cat <<EOF > /home/ubuntu/.ssh/internal
${internal_private_key}
EOF

    chmod 600 /home/ubuntu/.ssh/internal
    chown ubuntu:ubuntu /home/ubuntu/.ssh/internal
}


function set_env_variables() {
    sudo -u ubuntu bash -c 'cat <<EOF >> /home/ubuntu/.bashrc

# Custom environment variables
export CHARMHUB_URL=http://snapstore-proxy.canonical.internal
export OCI_REGISTRY_URL=http://oci-registry.canonical.internal:6000

export REGION="${region}"
export ARCHITECTURE="${architecture}"
export JUJU_VERSION="${juju_version}"
export LOCAL_JUJU="/home/ubuntu/.local/share/juju"
export JUJU_TOOLS_DIR="\$LOCAL_JUJU/tools"
export JUJU_AGENT_DIR="\$JUJU_TOOLS_DIR/released"

export VPC_ID="${vpc_id}"
export JUJU_CONTROLLER_AMI_ID="${juju_controller_ami_id}"
export JUJU_CONTROLLER_SUBNET_ID="${juju_controller_subnet_id}"
export JUJU_UNIT_AMI_ID="${juju_unit_ami_id}"
export JUJU_UNIT_SUBNET_ID="${juju_unit_subnet_id}"

export JUJU_CONFIG_FILE="/var/snap/juju/common/juju-config.yaml"

export K8S_INST_IP="${k8s_inst_ip}"
export STORE_INST_IP="${store_inst_ip}"

export KUBECONFIG=/home/ubuntu/.kube/config-remote-k8s

alias k="kubectl"
EOF'

    sudo -u ubuntu bash -c "source /home/ubuntu/.bashrc"
}


function generate_juju_metadata() {
    local JUJU_TOOLS_DIR="/home/ubuntu/.local/share/juju/tools"

    sudo -u ubuntu bash -c "juju metadata generate-agent-binaries --stream released"

    sudo -u ubuntu bash -c "mkdir -p $JUJU_TOOLS_DIR/metadata/controller"
    sudo -u ubuntu bash -c "
    juju metadata generate-image \
      -d \"$JUJU_TOOLS_DIR/metadata/controller\" \
      -i \"${juju_controller_ami_id}\" \
      -r \"${region}\" \
      -a \"${architecture}\" \
      -u \"https://ec2.${region}.amazonaws.com\" \
      --base \"ubuntu@22.04\" \
      --verbose
    "

    sudo -u ubuntu bash -l -c "mkdir -p $JUJU_TOOLS_DIR/metadata/unit"
    sudo -u ubuntu bash -l -c "
    juju metadata generate-image \
      -d \"$JUJU_TOOLS_DIR/metadata/unit\" \
      -i \"${juju_unit_ami_id}\" \
      -r \"${region}\" \
      -a \"${architecture}\" \
      -u \"https://ec2.${region}.amazonaws.com\" \
      --base \"ubuntu@22.04\" \
      --verbose
    "
}


function set_models_base_config() {
    local STORE_PROXY_URL="http://snapstore-proxy.canonical.internal"
    local OCI_REGISTRY_URL="http://oci-registry.canonical.internal:6000"
    local JUJU_TOOLS_DIR="/home/ubuntu/.local/share/juju/tools"

    sudo -u ubuntu bash -l -c "
    cat <<EOF | sudo tee /var/snap/juju/common/juju-config.yaml > /dev/null
charmhub-url: $STORE_PROXY_URL
snap-store-proxy-url: $STORE_PROXY_URL
vpc-id: ${vpc_id}
vpc-id-force: true
enable-os-refresh-update: false
enable-os-upgrade: false
image-metadata-defaults-disabled: true
container-image-metadata-defaults-disabled: true
agent-stream: released
image-stream: released
container-image-stream: released
agent-metadata-url: $JUJU_TOOLS_DIR
container-image-metadata-url: $OCI_REGISTRY_URL
EOF
    "
}


function setup_kubectl() {
    sudo -u ubuntu bash -c "mkdir ~/.kube"
    sudo -u ubuntu bash -c "ssh-keyscan -H ${k8s_inst_ip} >> /home/ubuntu/.ssh/known_hosts"

    retry --times 3 --delay 10 -- sudo -u ubuntu bash -c "
    ssh -i ~/.ssh/internal ubuntu@${k8s_inst_ip} -t 'while [ ! -d ~/.kube ]; do sleep 1; done; microk8s status --wait-ready; microk8s config > ~/.kube/config'
    "
    sudo -u ubuntu bash -c "scp -i ~/.ssh/internal ubuntu@${k8s_inst_ip}:/home/ubuntu/.kube/config ~/.kube/config-remote-k8s"
}


setup_ssh
set_env_variables
export_controller_sg_func
generate_juju_metadata
set_models_base_config
setup_kubectl
