To install gitops:
```bash
mkdir ~/git
cd ~/git
git clone https://github.com/mmwillingham/acm.git
cd acm
oc create -k install-gitops/
```
To get ArgoCD admin password
oc get secret -n openshift-gitops openshift-gitops-cluster -o json |jq -r .data[] | base64 -d && echo