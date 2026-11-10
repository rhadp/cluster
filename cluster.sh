source venv/bin/activate

SECRETS_FILE="${1:-.env}"
SECRETS_PATH="inventory/secrets/${SECRETS_FILE}"

if [ ! -f "$SECRETS_PATH" ]; then
  echo "Error: secrets file not found: $SECRETS_PATH" >&2
  exit 1
fi

set -a
source "$SECRETS_PATH"
set +a

INVENTORY_ARCH="arch-$CLUSTER_TOPOLOGY-$CLOUD_PROVIDER.yml"
echo "INVENTORY_ARCH: $INVENTORY_ARCH"

ansible-playbook -i "inventory/main.yml" -i "inventory/platform.yml" -i "inventory/${INVENTORY_ARCH}" cluster.yml
