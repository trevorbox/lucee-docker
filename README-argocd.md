# ArgoCD

See <https://docs.openshift.com/container-platform/4.7/cicd/gitops/configuring-sso-for-argo-cd-on-openshift.html>

Before starting, install the Red Hat Openshift GitOps and Namespace Configuration operators from OperatorHub.

```sh
export argocd_namespace=example-argocd
export argocd_tenant_namespace=example-argocd-tenant

helm upgrade -i argocd helm/argocd \
  --set subdomain=$(oc get configmap config -n openshift-apiserver -o jsonpath={.data.config\\.yaml} | jq -r .routingConfig.subdomain) \
  --set argocd.tenant.namespace=${argocd_tenant_namespace} \
  -n ${argocd_namespace} --create-namespace
```

Manually add the tenant namespace in the secret *example-default-cluster-config* 

```sh
oc patch secret example-default-cluster-config -n ${argocd_namespace} -p "{\"stringData\":{\"namespaces\":\"${argocd_namespace},${argocd_tenant_namespace}\"}}"
```

Create clusterrole and allow the namespace-configuration-operator to automatically create rolebindings in tenant namespaces when namespaces have `argocdserviceaccountname` & `argocdnamespace` annotations.

```sh
oc annotate namespace ${argocd_tenant_namespace} argocdserviceaccountname=${argocd_namespace}-application-controller
oc annotate namespace ${argocd_tenant_namespace} argocdnamespace=${argocd_namespace}
oc annotate namespace ${argocd_tenant_namespace} admins=user1,user3
helm upgrade -i argocd-namespace-configurations helm/namespace-configurations -n namespace-configuration-operator
```


Testing RBAC...

Within keycloak, the clients and scopes are already configured to work with Openshift. 

Create a Group called `ArgoCDAdmins` and assign a User (that has already logged into Keycloak) to it. Only users in this Group (besides the argo admin user) will have admin access to view and modify ArgoCD Applications, all other users won't be able to see anything.
