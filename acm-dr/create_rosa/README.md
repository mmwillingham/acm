## AWS setup
https://demo.redhat.com
Catalog > Lab > ROSA ILT
ssh to bastion as per email # You can also just use local terminal, but the bastion is already configured for AWS and ROSA and OCM

## Client Verification
```bash
rosa version
aws --version
aws sts get-caller-identity
rosa verify openshift-client
```

## Login to rosa
```bash
rosa login
rosa whoami
rosa verify quota
```

## Ensure ELB role exists
```bash
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" || aws iam create-service-linked-role --aws-service-name "elasticloadbalancing.amazonaws.com"
```

## Create account roles
```bash
# This only has to be done once per AWS account.
rosa create account-roles --mode auto --yes
# NOTE, at the end of the results, it provide the command to create OIDC (rosa create oidc-config). Do NOT run this.
```

## Create cluster
```bash
# Set environment variables. Edit these if desired.
export REGION=us-east-2
export OCP_VERSION=4.13.10
export CLUSTER_NAME=rosa-${GUID}

echo "export REGION=${REGION}" >>${HOME}/.bashrc
echo "export OCP_VERSION=${OCP_VERSION}" >>${HOME}/.bashrc
echo "export CLUSTER_NAME=${CLUSTER_NAME}" >>${HOME}/.bashrc

# Create the cluster
# This will also create the required operator roles and OIDC provider.
rosa create cluster \
  --cluster-name ${CLUSTER_NAME} \
  --version ${OCP_VERSION} \
  --region ${REGION} \
  --sts \
  --mode auto \
  --yes

# This will take about 40 minutes to run.
# To determine when your cluster is Ready:
rosa describe cluster -c $CLUSTER_NAME
# To watch your cluster installation logs:
rosa logs install -c $CLUSTER_NAME --watch
# Verify it is ready:
rosa list clusters

# Obtain the Console URL
rosa describe cluster -c ${CLUSTER_NAME} | grep Console

# Obtain the API URL
export API_URL=$(rosa describe cluster -c ${CLUSTER_NAME}|grep "API URL" | awk -c '{print $3}')
echo "export API_URL=${API_URL}" >> ${HOME}/.bashrc
```


