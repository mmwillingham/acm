# CFME lab: OpenShift 4 Post Install Conf ILT - AWS

# Reference: /home/martin/Documents/RedHat/Training/do480-2.4-student-guide.pdf
# Reference: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.5

# Prereq
sudo dnf install httpd-utils

# Create htpasswd users 
touch /tmp/htpasswd
htpasswd -Bb /tmp/htpasswd tom redhat
htpasswd -Bb /tmp/htpasswd mmw redhat
htpasswd -Bb /tmp/htpasswd martin redhat

#oc --user=admin create secret generic htpasswd --from-file=/tmp/htpasswd -n openshift-config
oc create secret generic htpass-secret --from-file=htpasswd=/tmp/htpasswd -n openshift-config
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


