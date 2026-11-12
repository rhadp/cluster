# Workshop setup

## Create the Automotive Suite Users

```shell
./workshop.sh
````

## Create the namespaces, per user01 .. user70

```shell

# clone the repo and create build namespace with the webhook
./examples/workshop/buildspace.sh GIT_REPO GIT_PAT user

# create the namespace used by Red Hat Dev Spaces
./examples/workshop/devspace.sh user
./examples/workshop/devspace-config.sh user GIT_PAT

```

## Update a user's repo from the upstream template

```shell
# upstream is detected (template or fork parent); pass it as 3rd arg to override
./examples/workshop/update-repo.sh OWNER/REPO-user GIT_PAT
```
