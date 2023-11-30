# Cluster Creation Dependencies
```mermaid
---
title: Cluster Creation</b>
---
flowchart TD
    <b>venafi-auth-policy-configuration</b> --> cert-manager-application
    <b>cluster-registration</b> --> openshift-gitops-operator
    <b>github-auth-policy-configuration</b> --> openshift-gitops-operator
    <b>secured-cluster-policy</b> --> acs-secured-configuration

  subgraph "ACM cluster</b>"
    xxx-cluster[<b>"xxx-cluster creates the managed cluster"</b>] -- contains --> cluster-registration["<b>cluster-registration</b>
    helm chart registers managed cluster to ACM
and deploys argocd and root app onto it"]
    venafi-auth-policy-configuration["<b>venafi-auth-policy-configuration</b>
    ACM policy sends venafi credentials 
    to the managed clusters"]
    github-auth-policy-configuration["<b>github-auth-policy-configuration</b>
    ACM policy sends github credentials 
    to the managed clusters"]
    secured-cluster-policy["<b>secured-cluster-policy</b>
    ACM policy sends ACS bundle 
    to the managed clusters"]
  end

  subgraph "<b>Managed cluster</b>"
    <b>openshift-gitops-operator</b> --> cert-manager-operator
    <b>cert-manager-operator</b> --> cert-manager-application["<b>cert-manager-application</b>
    runs job to create venafi token 
    from venafi credentials, 
    then configures venafi cert issuer"]
    <b>cert-manager-application</b> --> ingress-controller-configuration["<b>ingress-controller-configuration</b>
    installs 53 cert 
    on the cluster ingress"]
    <b>cert-manager-application</b> --> openshift-api-certs-application["<b>openshift-api-certs-application</b>
    installs 53 cert 
    for the OCP API"]
    <b>openshift-api-certs-application</b> --> vault-config-operator
    <b>vault-config-operator</b> --> vault-configuration["<b>vault-configuration</b>
    configures access to vault for 
    extracting infra secrets"]
   <b> nmstate-operator</b> --> nmstate-configuration["<b>nmstate-configuration</b>
    allows access to storage network"]
   <b> namespace-config-operator</b> --> namespace-configuration["<b>namespace-configuration</b>
    deploys ESO secret store 
    to infra namespaces"]
    <b>vault-configuration</b> --> namespace-configuration
    <b>external-secret-operator</b> --> namespace-configuration
    <b>powerflex-csm-operator</b> --> powerflex-csm-configuration["<b>powerflex-csm-configuration</b>
    deploys CSI storage
    class for cluster"]
    <b>namespace-configuration</b> --> powerflex-csm-configuration
    <b>nmstate-configuration</b> --> powerflex-csm-configuration
    <b>acs-operator</b> --> acs-secured-configuration["<b>acs-secured-configuration</b>
    registers cluster to ACS"] 
  end








```
