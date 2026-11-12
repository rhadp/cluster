#!/usr/bin/env bash

set -e

if [ "$#" -ne 2 ]; then
  echo "Usage: $(basename "$0") <username> <PAT>" >&2
  echo "  username: the user to create the secrets for (must run as cluster-admin)." >&2
  echo "  PAT: the Personal Access Token to use for setting up the secrets." >&2
  exit 1
fi

USER_NAME=$1
GIT_PAT=$2

oc get user "$USER_NAME" &>/dev/null || {
  echo "Warning: user $USER_NAME not found" >&2
  #exit 1
}

# Create a devspaces namespace
NAMESPACE="devspaces-$USER_NAME"
echo "NAMESPACE: $NAMESPACE"

GIT_CREDENTIALS_B64=$(printf '%s' "https://$USER_NAME:$GIT_PAT@github.com" | base64 | tr -d '\n')
GIT_PAT_B64=$(printf '%s' "$GIT_PAT" | base64 | tr -d '\n')

oc create -f- <<-EOF
kind: Secret
apiVersion: v1
metadata:
  name: git-credentials-secret
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/component: workspace-secret
    app.kubernetes.io/part-of: che.eclipse.org
    controller.devfile.io/git-credential: 'true'
    controller.devfile.io/watch-secret: 'true'
  annotations:
    che.eclipse.org/automount-workspace-secret: 'true'
    che.eclipse.org/git-credential: 'true'
    che.eclipse.org/mount-as: file
    che.eclipse.org/mount-path: /.git-credentials
    che.eclipse.org/scm-url: 'https://github.com'
    controller.devfile.io/mount-path: /.git-credentials
data:
  credentials: $GIT_CREDENTIALS_B64
type: Opaque
EOF

oc create -f- <<-EOF
kind: Secret
apiVersion: v1
metadata:
  name: personal-access-token-git-pac
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/component: scm-personal-access-token
    app.kubernetes.io/part-of: che.eclipse.org
  annotations:
    che.eclipse.org/scm-personal-access-token-name: github
    che.eclipse.org/scm-provider-name: github
    che.eclipse.org/scm-url: 'https://github.com/'
data:
  token: $GIT_PAT_B64
type: Opaque
EOF

oc create -f- <<-EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: workspace-userdata-gitconfig-configmap
  namespace: $NAMESPACE
  labels:
    controller.devfile.io/mount-to-devworkspace: 'true'
    controller.devfile.io/watch-configmap: 'true'
  annotations:
    controller.devfile.io/mount-as: subpath
    controller.devfile.io/mount-path: /etc/
data:
  gitconfig: |
    [filter "lfs"]
        clean = git-lfs clean -- %f
        smudge = git-lfs smudge -- %f
        process = git-lfs filter-process
        required = true

    [credential]
        helper = "!f() { test \"$1\" = get && git credential-store --file /.git-credentials/credentials \"$@\"; }; f"
        
    [user]
    name="$USER_NAME"
    email="$USER_NAME@example.com"
EOF