# ArgoCD

See <https://docs.openshift.com/container-platform/4.7/cicd/gitops/configuring-sso-for-argo-cd-on-openshift.html>

Before starting, install the Red Hat Openshift GitOps and Namespace Configuration operators from OperatorHub.

```sh
export argocd_namespace=example-argocd
export argocd_tenant_namespace=example-argocd-tenant

oc new-project ${argocd_namespace}
oc new-project ${argocd_tenant_namespace} 

helm upgrade -i keycloak-operator helm/keycloak-operator -n ${argocd_namespace}

# wait for the operator...

helm upgrade -i keycloak helm/keycloak -n ${argocd_namespace}


helm upgrade -i argocd helm/argocd \
  --set subdomain=$(oc get configmap config -n openshift-apiserver -o jsonpath={.data.config\\.yaml} | jq -r .routingConfig.subdomain) \
  -n ${argocd_namespace} --create-namespace

export client_secret=$(oc get secret keycloak-client-secret-argocd -n ${argocd_namespace} -o jsonpath={.data.CLIENT_SECRET})
oc patch secret argocd-secret -n ${argocd_namespace} -p "{\"data\":{\"oidc.keycloak.clientSecret\":\"${client_secret}\"}}"
```

Within keycloak, the clients and scopes are already configured to work with Openshift. 

Create a Group called `ArgoCDAdmins` and assign a User (that has already logged into Keycloak) to it. Only users in this Group (besides the argo admin user) will have admin access to view and modify ArgoCD Applications, all other users won't be able to see anything.

Manually add the tenant namespace in the secret *example-default-cluster-config* 

```sh
oc patch secret example-default-cluster-config -n ${argocd_namespace} -p "{\"stringData\":{\"namespaces\":\"${argocd_namespace},${argocd_tenant_namespace}\"}}"
```

Create clusterrole and allow the namespace-configuration-operator to automatically create rolebindings in tenant namespaces when namespaces have `argocdserviceaccountname` & `argocdnamespace` annotations.

```sh
oc annotate namespace ${argocd_tenant_namespace} argocdserviceaccountname=${argocd_namespace}-application-controller
oc annotate namespace ${argocd_tenant_namespace} argocdnamespace=${argocd_namespace}
helm upgrade -i argocd-namespace-configurations helm/namespace-configurations -n namespace-configuration-operator
```

Deploy Argocd Application...

```sh
helm upgrade -i argocd-application helm/argocd-application \
  --set argocd.tenant.namespace=${argocd_tenant_namespace} \
  -n ${argocd_namespace} --create-namespace
```
