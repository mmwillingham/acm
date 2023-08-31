# CFME lab: OpenShift 4 Post Install Conf ILT - AWS

# Reference: /home/martin/Documents/RedHat/Training/do480-2.4-student-guide.pdf
# Reference: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.5

# Create htpasswd users 
touch htpasswd
htpasswd -Bb htpasswd tom redhat
htpasswd -Bb htpasswd mmw redhat
htpasswd -Bb htpasswd martin redhat

oc --user=admin create secret generic htpasswd --from-file=htpasswd -n openshift-config
oc replace -f - <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: Local Password
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd
EOF
oc adm groups new mylocaladmins
oc adm groups add-users mylocaladmins tom mmw martin
oc adm policy add-cluster-role-to-group cluster-admin mylocaladmins

