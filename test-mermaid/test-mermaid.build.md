# Cluster Creation Dependencies
```mermaid
flowchart TD
A --> B
#---

#title: Cluster Creation

#---

#flowchart TD
A --> B
#  venafi-auth-policy-configuration --> cert-manager-application
#    cluster-registration --> openshift-gitops-operator
#    github-auth-policy-configuration --> openshift-gitops-operator
#    secured-cluster-policy --> acs-secured-configuration
#
#  subgraph ACM cluster
#    xxx-cluster["xxx-cluster creates the managed cluster"] -- contains --> cluster-registration["<b>cluster-registration</b>
#    helm chart registers managed cluster to ACM
#    and deploys argocd and root app onto it"]
#    venafi-auth-policy-configuration["<b>venafi-auth-policy-configuration</b>
#    ACM policy sends venafi credentials 
#    to the managed clusters"]
#    github-auth-policy-configuration["<b>github-auth-policy-configuration</b>
#    ACM policy sends github credentials 
#    to the managed clusters"]
#    secured-cluster-policy["<b>secured-cluster-policy</b>
#    ACM policy sends ACS bundle 
#    to the managed clusters"]
#  end
#
#  subgraph Managed cluster
#    openshift-gitops-operator --> cert-manager-operator
#    cert-manager-operator --> cert-manager-application["<b>cert-manager-application</b>
#    runs job to create venafi token 
#    from venafi credentials, 
#    then configures venafi cert issuer"]
#    cert-manager-application --> ingress-controller-configuration["<b>ingress-controller-configuration</b>
#    installs 53 cert 
#    on the cluster ingress"]
#    cert-manager-application --> openshift-api-certs-application["<b>openshift-api-certs-application</b>
#    installs 53 cert 
#    for the OCP API"]
#    openshift-api-certs-application --> vault-config-operator
#    vault-config-operator --> vault-configuration[vault-configuration</b>
#    configures access to vault for 
#    extracting infra secrets"]
#    nmstate-operator --> nmstate-configuration["<b>nmstate-configuration</b>
#    allows access to storage network"]
#    namespace-config-operator --> namespace-configuration["<b>namespace-configuration</b>
#    deploys ESO secret store 
#    to infra namespaces"]
#    vault-configuration --> namespace-configuration
#    external-secret-operator --> namespace-configuration
#    powerflex-csm-operator --> powerflex-csm-configuration["<b>powerflex-csm-configuration</b>
#    deploys CSI storage
#    class for cluster"]
#    namespace-configuration --> powerflex-csm-configuration
#    nmstate-configuration --> powerflex-csm-configuration
#    acs-operator --> acs-secured-configuration["<b>acs-secured-configuration</b>
#    registers cluster to ACS"] 
#  end
#
```
