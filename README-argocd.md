# ArgoCD

See <https://docs.openshift.com/container-platform/4.7/cicd/gitops/configuring-sso-for-argo-cd-on-openshift.html>

## Setup
Before starting, install the Red Hat Openshift GitOps and Namespace Configuration operators from OperatorHub.

```sh
export argocd_namespace=tbox-gitops
export argocd_tenant_namespace=tbox-apps
export argocd_name=tbox-gitops
export subdomain=$(oc get configmap config -n openshift-apiserver -o jsonpath={.data.config\\.yaml} | jq -r .routingConfig.subdomain)

oc new-project ${argocd_namespace}
oc new-project ${argocd_tenant_namespace} 
```

## Install the keycloak operator

```sh
helm upgrade -i keycloak-operator helm/keycloak-operator -n ${argocd_namespace}
```

Wait for the operator to install...

## Deploy keycloak

```sh
helm upgrade -i keycloak helm/keycloak -n ${argocd_namespace} \
  --set argocd.name=${argocd_name} \
  --set argocd.namespace=${argocd_namespace} \
  --set subdomain=${subdomain}
```

Wait for keyloak to deploy...

## Create keycloak group 

Since there is no CRD to create the keycloak Group `ArgoCDAdmins`, we can instead create it programmatically...

```sh
export admin_password=$(oc get secret credential-keycloak -n ${argocd_namespace} -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d)
export keycloak_podip=$(oc get pod keycloak-0 -n ${argocd_namespace} -o jsonpath={.status.podIP})
oc exec -n ${argocd_namespace} keycloak-0 -- /opt/eap/bin/kcadm.sh config credentials --server http://${keycloak_podip}:8080/auth --realm master --user admin --password ${admin_password} --config /tmp/kcadm.config
oc exec -i -n ${argocd_namespace} keycloak-0 -- /opt/eap/bin/kcadm.sh create groups -r argocd -s name="ArgoCDAdmins" -i --config /tmp/kcadm.config
```

## Deploy keycloak users

Programmatically grab the uids of users. Usually users need to have logged into the cluster prior to there being a User object created in OCP.

```sh
export user1_uid=$(oc get user user1 -o jsonpath={.metadata.uid})
export user2_uid=$(oc get user user2 -o jsonpath={.metadata.uid})
export user3_uid=$(oc get user user3 -o jsonpath={.metadata.uid})
export user4_uid=$(oc get user user4 -o jsonpath={.metadata.uid})

envsubst < helm/keycloak-users/values-envsubst.yaml > helm/keycloak-users/values-out.yaml

helm upgrade -i keycloak-users helm/keycloak-users -n ${argocd_namespace} -f helm/keycloak-users/values-out.yaml
```

## Deploy argocd

```sh
helm upgrade -i argocd helm/argocd -n ${argocd_namespace} \
  --set argocd.name=${argocd_name} \
  --set subdomain=${subdomain}
```

Wait for argocd to deploy...

## Add tenant namespace to argocd 

Manually add the tenant namespace in the secret *${argocd_name}-default-cluster-config* 

```sh
oc patch secret ${argocd_name}-default-cluster-config -n ${argocd_namespace} -p "{\"stringData\":{\"namespaces\":\"${argocd_namespace},${argocd_tenant_namespace}\"}}"
```

## Configure the client secret used by argocd with keycloak

```sh
export client_secret=$(oc get secret keycloak-client-secret-argocd -n ${argocd_namespace} -o jsonpath={.data.CLIENT_SECRET})

oc patch secret argocd-secret -n ${argocd_namespace} -p "{\"data\":{\"oidc.keycloak.clientSecret\":\"${client_secret}\"}}"
```

## Restart the server pod to pickup new keycloak client secret

```sh
oc rollout restart deploy/${argocd_name}-server -n ${argocd_namespace}
```

## Log into argocd to create a user in keycloak

```sh
echo Open argocd and login to create your user: https://$(oc get route ${argocd_name}-server -n ${argocd_namespace} -o jsonpath={.spec.host})
```

## Configure keycloak Group

Within keycloak, the clients and scopes are already configured to work with Openshift. 

Create a Group called `ArgoCDAdmins` and assign a User (that has already logged into Keycloak) to it. Only users in this Group (besides the argo admin user) will have admin access to view and modify ArgoCD Applications, all other users won't be able to see anything.

## Configure argocd serviceaccount rolebindings in tenant namespaces using namespace-config

Create clusterrole and allow the namespace-configuration-operator to automatically create rolebindings in tenant namespaces when namespaces have `argocdserviceaccountname` & `argocdnamespace` annotations.

```sh
oc annotate namespace ${argocd_tenant_namespace} argocdserviceaccountname=${argocd_name}-argocd-application-controller
oc annotate namespace ${argocd_tenant_namespace} argocdnamespace=${argocd_namespace}
helm upgrade -i argocd-namespace-configurations helm/namespace-configurations -n namespace-configuration-operator
```

## Deploy argocd Application

```sh
helm upgrade -i argocd-application helm/argocd-application \
  --set argocd.tenant.namespace=${argocd_tenant_namespace} \
  -n ${argocd_namespace}
```
