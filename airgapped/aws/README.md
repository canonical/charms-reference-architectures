# charms-aws-airgapped
A repo for building a test/dev environment for airgapped deployments of charms in AWS

**Note:** *this repo is purely destined for development / testing, NOT production.*

----

The workflow will happen in 2 stages:

## A. Image building + base cloud environment
This part should only run once, and the outcome is reusable.

The base directory for the TF project is `env/`.

### 1. S3 bucket for terraform state
Create an S3 bucket to store the terraform state of the environment setup. Then set its path in:
`env/main.tf`
```
terraform {
  backend "s3" {
    bucket = "xyz-airgapped-env-tfstate-abc"
    key    = "env.tfstate"
    region = "us-east-1"
  }
}
```

### 2. Create an ubuntu dev account (without 2FA) 
Use the credentials you created and put them in: `env/scripts/snapstore-proxy-oci-registry/ami-setup-store.sh`
```
EMAIL="xxxx@gmail.com\r"
PASSWORD="xxxx\r"
```

**Note:** This is unsafe, and for the future, we'll propagate them correctly though env variables.

### 3. List the snaps, charms and bundle you wish to export
In `env/scripts/snapstore-proxy-oci-registry/resources.yaml`, list all resources you wish to deploy in an airgapped environment.

### 4. Deploy:

Due to the lack of VPC private endpoints in all AWS regions, the only supported region is `us-east-1`
```
cd env
tf init
tf plan -out terraform.out -var='region=us-east-1' -var='team=<your-team>'
tf apply
```

This will output: 
- 1 VPC id with the cidr block `10.0.0.0/16`
- 5 private subnet IDs:
  - `subnet_vpn`: the subnet where the VPN (wireguard) instance will be running
    - This will be the only instance in the deployment with internet access
    - This will be the only instance with a public IP
    - cidr block: `10.0.4.0/24`
  - `subnet_bastion`: the private subnet in which the bastion instance will be hosted:
    - cidr block `10.0.0.0/24`
  - `subnet_snap_store_proxy`: the private subnet in which the snap-store-proxy as well as the OCI registry instance will be hosted.
    - cidr block: `10.0.10/24`
  - `subnet_juju_controller`: the private subnet in which the controller instance(s) will be running
    - cidr block: `10.0.2.0/24`
  - `subnet_juju_apps`: the private subnet in which all Juju units will be running (incl. the microk8s instance)
    - cidr block: `10.0.3.0/24`
- 5 AMI IDs:
  - `bastion_ami`: The image that will be used to provision the bastion instance from where to operate your deployments.
  - `estore_ociregistry_ami`: The image where the snap store proxy is installed and configured, where snaps and charms are loaded and where OCI images are loaded in an OCI registry. The instance provisioned with this image will host:
    - the snap store proxy
    - the OCI registry 
    - all the packages
  - `juju_controller_ami`: the image used to provision juju controllers
  - `juju_machine_apps_ami`: the image used to provision juju units for VM models
  - `juju_k8s_apps_ami`: the image used to provision a microk8s instance for K8s models

The entire deployment should take around 45min - 60min, but it should only be happening once.

----
## B. Development and charms infrastructure:
This part is about setting up the development / testing environment. Destroying and recreating your environment should be simple and fast.

The base directory for the TF project is `deployment/`.

### 1. In AWS `us-east-1`, create an SSH key-pair named: `admin`
This will allow you to ssh into:
- the VPN instance 
- the bastion instance

### 2. In your local environment, generate an ssh key pair named `internal`
This will allow you to ssh from the bastion into: 
- the snap-store-proxy / oci-registry instance
- the microk8s instance

```
cd deployment/keys
ssh-keygen -t rsa -b 4096 -f internal -C "key to ssh from bastion -> store + microk8s"
```
**Note:** The keys need to be located in `deployment/keys`

### 3. Prepare your local machine for the vpn access
This should allow you to access your bastion instance through a wireguard instance 

```
> bash client-setup.sh

Generating key pair...

VPN Client public key - paste it into the VPN server's /etc/wireguard/wg0.conf in the Peer/PublicKey section
(If you're using terraform, put it in the variable 'vpn_client_public_key': 
AC2V/LoZwh/I3iXycPd056SefBT0qmM+6cd9uzgcXC0=
```
Copy the key, and stop there. Open a new terminal tab. 

### 4. S3 bucket for terraform state
Ensure that the previously created bucket for the TF state is well referenced in your `main.tf` 
`deployment/main.tf`
```
terraform {
  backend "s3" {
    bucket = "xyz-airgapped-env-tfstate-abc"
    key    = "env.tfstate"
    region = "us-east-1"
  }
}
```

### 5. Deploy your infrastructure:
This will create all the necessary infrastructure for your development environment. Notably, this will give you:
- 1 vpn / wireguard instance 
- 1 bastion instance 
- 1 store / registry instance 
- 1 microk8s instance

Open a new terminal tab and ensure your client's VPN public key is passed as a variable:
```
cd deployment/
tf plan -out terraform.out \
  -var='region=us-east-1' \
  -var='team=<your-team>' \
  -var='vpn_client_public_key=AC2V/LoZwh/I3iXycPd056SefBT0qmM+6cd9uzgcXC0='
```

This should give you 2 outputs:
- `public_ip_vpn`: the public IP of your VPN instance
- `private_ip_bastion`: the private ip of your bastion instance

### 6. Complete your vpn client configuration:
Go back to your vpn configuration terminal tab and complete the flow, paste the `public_ip_vpn` value into the prompt.
```
Enter the VPN Server instance's Public IP: <public_ip_vpn>

Enter the VPN Server key's public key (sudo cat /etc/wireguard/server.pub): ABCD
```
to fill the last prompt, ssh into your VPN instance (using the `admin` key) and  paste it there.
```
ssh -i admin.key ubuntu@<public_ip_vpn> -t "sudo cat /etc/wireguard/server.pub"
```

### 7. Access your bastion:
Once your local vpn client is configured, you can ssh into your bastion instance using its private IP, using the `admin` key.
```
ssh -i admin.key ubuntu@<private_ip_bastion>
```

----
## C. Juju and charms deployment:
This final part is about creating your juju environment and deploying charms.
The commands can be copy/pasted as they reference environment variables already exported in the bastion.

### 1. Add your aws credentials:
```
juju add-credential aws
```

### 2. Generate juju metadata:
```
juju metadata generate-agent-binaries --stream released

juju metadata generate-image \
  -d "${JUJU_TOOLS_DIR}/metadata/controller" \
  -i "${JUJU_CONTROLLER_AMI_ID}" \
  -r "${REGION}" \
  -a "${ARCHITECTURE}" \
  -u "https://ec2.${REGION}.amazonaws.com" \
  --base "ubuntu@22.04"

juju metadata generate-image \
  -d "${JUJU_TOOLS_DIR}/metadata/unit" \
  -i "${JUJU_UNIT_AMI_ID}" \
  -r "${REGION}" \
  -a "${ARCHITECTURE}" \
  -u "https://ec2.${REGION}.amazonaws.com" \
  --base "ubuntu@22.04"
```

### 3. Bootstrap a machine controller and apply security groups:
```
juju bootstrap aws/${REGION} \
  aws \
  --bootstrap-base ubuntu@22.04 \
  --agent-version "${JUJU_VERSION}" \
  --metadata-source "${JUJU_TOOLS_DIR}/metadata/controller" \
  --bootstrap-constraints instance-type="t2.medium" \
  --bootstrap-constraints arch="amd64" \
  --bootstrap-constraints root-disk=75G \
  --bootstrap-constraints image-id="${JUJU_CONTROLLER_AMI_ID}" \
  --bootstrap-constraints instance-role="juju-controller-instance-profile" \
  --constraints allocate-public-ip=false \
  --constraints image-id="${JUJU_CONTROLLER_AMI_ID}" \
  --constraints instance-role="juju-controller-instance-profile" \
  --to subnet="${JUJU_CONTROLLER_SUBNET_ID}" \
  --config "${JUJU_CONFIG_FILE}" \
  --config image-metadata-url="${JUJU_TOOLS_DIR}/metadata/controller/images"

apply_security_groups
```

### 4. Create a machine model:
```
juju add-model dev-vm \
  aws/us-east-1 \
  --config /var/snap/juju/common/juju-config.yaml \
  --config image-metadata-url="${JUJU_TOOLS_DIR}/metadata/unit/images"
```

### 4. Deploy a VM charm:
```
juju deploy \
  -n 1 \
  self-signed-certificates \
  --channel latest/stable \
  --base ubuntu@22.04 \
  --constraints allocate-public-ip=false \
  --constraints image-id="${JUJU_UNIT_AMI_ID}" \
  --constraints instance-role="juju-unit-instance-profile" \
  --constraints instance-type="t2.small" \
  --constraints arch="amd64" \
  --constraints root-disk=75G \
  --to subnet="${JUJU_UNIT_SUBNET_ID}"

juju deploy \
  -n 3 \
  opensearch \
  --channel 2/edge \
  --base ubuntu@22.04 \
  --constraints allocate-public-ip=false \
  --constraints image-id="${JUJU_UNIT_AMI_ID}" \
  --constraints instance-role="juju-unit-instance-profile" \
  --constraints instance-type="t2.medium" \
  --constraints arch="amd64" \
  --constraints root-disk=75G \
  --to subnet="${JUJU_UNIT_SUBNET_ID}",subnet="${JUJU_UNIT_SUBNET_ID}",subnet="${JUJU_UNIT_SUBNET_ID}"
```

### 5. Create a k8s model:
```
juju add-k8s myk8scloud --client --controller aws

juju add-model dev-k8s \
  myk8scloud \
  --config /var/snap/juju/common/juju-config.yaml \
  --config container-image-metadata-url="${JUJU_TOOLS_DIR}/metadata/unit/images" \
  --config image-metadata-url="${JUJU_TOOLS_DIR}/metadata/unit/images"
```

### 6. Deploy a k8s app:
Find out the images you had exported as part of your AMI building process.
```
curl -s http://oci-registry.canonical.internal:6000/v2/_catalog | jq .
curl -s http://oci-registry.canonical.internal:6000/v2/charm/ai79kfdcsgq83re7pz3a8ru02irx26r0bkqc8/mongodb-image/tags/list | jq .
```

Then deploy your k8s charms by pointing to the right resource.
```
juju deploy \
  -n 3 \
  mongodb-k8s \
  --channel 6/edge \
  --base ubuntu@22.04 \
  --constraints instance-role="juju-unit-instance-profile" \
  --trust \
  --resource mongodb-image=oci-registry.canonical.internal:6000/charm/ai79kfdcsgq83re7pz3a8ru02irx26r0bkqc8/mongodb-image:latest
```

Your ec2 controller is now managing both a machine and a k8s model. 

---

## D. Cleanup your environment
After completing your dev / testing
1. destroy juju resources through juju (This will ensure that all the juju instances and the resources are well destroyed like security groups etc.):
      - `juju remove-application app --destroy-storage...`
      - `juju destroy-model dev-vm --destroy-storage..`
      - `juju destroy-model dev-k8s --destroy-storage...`
      - `juju destroy-controller aws --destroy-storage ...`
2. cleanup instances created with TF
    ```
    cd deployment/
    tf destroy -var='team=<your-team>' -var='vpn_client_public_key=123'  
    ```
3. **ONLY If you're fully done with this work:** cleanup the overall environment
    1. Cleanup all the managed infrastructure 
       ```
       cd env/
       tf destroy -var=<your-team>
       ```
    2. Remove ALL created AMIs
    3. Remove ALL the snapshots associated with those AMIs
    4. Remove the S3 bucket used to store the TF state.
---

## E. Known issues / improvement points:
1. The ubuntu credentials should be propagated through environment variables instead of from within the code
2. The juju version is currently hardcoded to `3.6.5` in many places, it should become parameterizable
3. Not all resources are tagged
4. Only the `us-east-1` region is supported, this is due to aws limiting the use of private vpc endpoints to only this region.
5. The `client-setup.sh` needs to be adapted for linux clients.
