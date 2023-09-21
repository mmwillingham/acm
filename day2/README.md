To install day2 app-of-apps:
```bash
mkdir ~/git
cd ~/git
git clone https://github.com/mmwillingham/acm.git
cd acm
oc create -f day2/app-day2.yaml

# ACM operator takes a couple of minutes then MCH takes 5-10 minutes to be fully installed. Check multiclusterhub for it to be ready.
mch_status=$(oc get -n open-cluster-management $(oc -n open-cluster-management get mch -o name) -ojson | jq -r '.status.phase')
expected_condition="Running"
until [ "$mch_status" = "$expected_condition" ]
do
  oc -n open-cluster-management get mch | grep multiclusterhub
  sleep 5
done
```
