# Install ACM on hub cluster
## Prereqs to be run from CLI
## clone git repo
```bash
mkdir ~/git
cd ~/git
git clone https://github.com/mmwillingham/acm.git
cd acm
```
## To install ACM on hub cluster
## (Check version of ACM in subscription within the file installhub.sh)
### login to OCP
```bash
oc -u login <etc>
. install-acm/installhub.sh # Note, you initially see an error "Required resource not specified" but after a few seconds, the progress will be shown.
# There is an issue in the loop so that it doesn't end when the operator is successfully installed. Just CTRL-C and re-run
```
## Create clusterset for hub & managed
```bash
oc apply -f install-acm/create-clusterset-hub.yaml
oc apply -f install-acm/create-clusterset-managed.yaml
oc get managedclusterset
```

## Assign new clusterset to hub cluster
```bash
oc label --overwrite managedclusters.cluster.open-cluster-management.io local-cluster cluster.open-cluster-management.io/clusterset=hub
oc get managedclusterset
```

## Add kubeadmin (and other desired users) to subscription-admin cluster-role-binding
```bash
oc apply -f install-acm/patch-subscription-kubeadmin.yaml
oc apply -f install-acm/patch-subscription-cluster-admin.yaml
```
#
# All in one
#
```bash
#export ocp_api="https://api.rosa-pq5k9.gogx.p1.openshiftapps.com:6443"
export ocp_api="https://api.rosa-frft4.7mmq.p1.openshiftapps.com:6443"
export ocp_user="cluster-admin"
export ocp_pass="<redacted>"
echo $ocp_user 
echo $ocp_pass
echo $ocp_api
oc login -u $ocp_user $ocp_api # -p $ocp_pass
oc get nodes
# Verify you see nodes before proceeding
mkdir ~/git
cd ~/git
git clone https://github.com/mmwillingham/acm.git
cd acm
. install-acm/installhub.sh
oc apply -f install-acm/create-clusterset-hub.yaml
oc apply -f install-acm/create-clusterset-managed.yaml
oc get managedclusterset
oc label --overwrite managedclusters.cluster.open-cluster-management.io local-cluster cluster.open-cluster-management.io/clusterset=hub
oc get managedclusterset
oc apply -f install-acm/patch-subscription-kubeadmin.yaml
oc apply -f install-acm/patch-subscription-cluster-admin.yaml

```
