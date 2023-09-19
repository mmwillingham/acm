To get ArgoCD admin password
oc get secret -n openshift-gitops openshift-gitops-cluster -o json |jq -r .data[] | base64 -d && echo