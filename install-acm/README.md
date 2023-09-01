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
```bash
. install-acm/installhub.sh
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
