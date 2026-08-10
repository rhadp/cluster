source venv/bin/activate

set -a
source inventory/secrets/.env
set +a

INVENTORY_ARCH="arch-$CLUSTER_TOPOLOGY-$CLOUD_PROVIDER.yml"
echo "INVENTORY_ARCH: $INVENTORY_ARCH"

ansible-playbook -i "inventory/main.yml" -i "inventory/platform.yml" -i "inventory/${INVENTORY_ARCH}" platform.yml