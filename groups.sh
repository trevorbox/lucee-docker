#!/bin/bash

set -ex

export argocd_namespace=example-argocd
export admin_password=$(oc get secret keycloak-secret -n ${argocd_namespace} -o jsonpath='{.data.SSO_PASSWORD}' | base64 -d)
export admin_username=$(oc get secret keycloak-secret -n ${argocd_namespace} -o jsonpath='{.data.SSO_USERNAME}' | base64 -d)
export argocd_realm=argocd


echo "* Request for authorization"

export keycloak_route=$(oc get route keycloak -n ${argocd_namespace} -o jsonpath='{.spec.host}')

export TKN=$(curl -X POST "https://${keycloak_route}/auth/realms/${argocd_realm}/protocol/openid-connect/token" \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "username=${admin_username}" \
 -d "password=${admin_password}" \
 -d 'grant_type=password' \
 -d 'client_id=admin-cli' | jq -r '.access_token')

curl -X POST "https://${keycloak_route}/auth/realms/${argocd_realm}/groups" \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $TKN" \
-d '{"name": "ArgoCDAdmins"}' | jq .


# curl -X GET "https://${keycloak_route}/auth/admin/realms/ocp/groups/e8af1625-83be-48b2-afb4-44311a1a27e4" \
# -H "Accept: application/json" \
# -H "Authorization: Bearer $TKN" | jq .
