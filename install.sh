source venv/bin/activate 
source inventory/secrets/.env

INVENTORY_ARCH="arch-$CLUSTER_TOPOLOGY-$CLOUD_PROVIDER.yml"
echo "INVENTORY_ARCH: $INVENTORY_ARCH"

ansible-playbook -i "inventory/main.yml" -i "inventory/${INVENTORY_ARCH}" 1_bootstrap_cluster.yml