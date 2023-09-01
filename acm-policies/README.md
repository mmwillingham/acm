# Create the ACM application subscription

## Create acm-policies namespace
```bash
oc new-project acm-policies
```

## Create ACM application to run policies
```bash
oc apply -f main-policy.yaml
```


## The following steps are optional.
## For policy generator - if using native ACM application subscription, no need to enable policyGenerator - it is already present.
### To test at cli - follow these steps (examples below)
#### Docs
##### https://github.com/open-cluster-management-io/policy-generator-plugin/tree/main
#### These steps are shorter for installing policyGenerator
##### https://cloud.redhat.com/blog/generating-governance-policies-using-kustomize-and-gitops

### Install PolicyGenerator
```bash
mkdir -p ${HOME}/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator
curl -L \
  -o ${HOME}/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator/PolicyGenerator \
  https://github.com/stolostron/policy-generator-plugin/releases/download/v1.8.0/linux-amd64-PolicyGenerator
chmod +x ${HOME}/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator/PolicyGenerator
```
### Test at CLI - two methods
#### As a plugin
cd base
kustomize build --enable-alpha-plugins

#### Directly at a policyGenerator config
PolicyGenerator policygenerator.yaml


### Install PolicyGenerator (Older steps)
### Download PolicyGenerator to ~/Downloads
#### https://github.com/open-cluster-management-io/policy-generator-plugin/releases

```bash
mkdir -p ${HOME}/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator
chmod +x ~/Downloads/linux-amd64-PolicyGenerator
mv linux-amd64-PolicyGenerator ${HOME}/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator/PolicyGenerator
sudo dnf install go # may need to connect to VPN first
GOBIN=${HOME}/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator \
go install open-cluster-management.io/policy-generator-plugin/cmd/PolicyGenerator@latest
```



