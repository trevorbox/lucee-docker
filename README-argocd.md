# ArgoCD

See <https://docs.openshift.com/container-platform/4.7/cicd/gitops/configuring-sso-for-argo-cd-on-openshift.html>

## Setup
Before starting, install the Red Hat Openshift GitOps and Namespace Configuration operators from OperatorHub.

```sh
export argocd_namespace=a-team-gitops
export argocd_tenant_namespace=a-team-gitops-application
export argocd_name=a-team
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
