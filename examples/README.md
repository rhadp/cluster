# Examples

Create a devspaces workspace for each user:

```shell
./devspaces-namespace.sh <username>
```

Replace the default builder config:

```shell
oc delete operatorconfig config -n automotive-dev-operator-system
oc apply -f oc-auto-builder.yaml
```
