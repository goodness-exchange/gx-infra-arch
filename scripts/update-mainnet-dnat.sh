#!/bin/bash
# Update DNAT rules on mainnet nodes when ingress controller pod IP changes
# Run this script from VPS4 (or any node with kubectl access)

set -e

# Mainnet node IPs
VPS1="72.60.210.201"
VPS2="72.61.116.210"
VPS3="72.61.81.3"

# Get current ingress controller pod IP
INGRESS_POD_IP=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.podIP}')

if [ -z "$INGRESS_POD_IP" ]; then
    echo "ERROR: Could not get ingress controller pod IP"
    exit 1
fi

echo "Current ingress controller pod IP: $INGRESS_POD_IP"

# Function to update DNAT rules on a node
update_node() {
    local node_ip=$1
    local node_name=$2

    echo "=== Updating $node_name ($node_ip) ==="

    ssh root@$node_ip "
        # Remove old DNAT rules for ports 80/443
        iptables -t nat -S PREROUTING | grep -E 'dpt:80.*DNAT|dpt:443.*DNAT' | while read rule; do
            iptables -t nat \$(echo \$rule | sed 's/-A/-D/')
        done 2>/dev/null || true

        # Remove old MASQUERADE rules for ingress pod
        iptables -t nat -S POSTROUTING | grep -E '10\.42\.[0-9]+\.[0-9]+.*dpt:(80|443).*MASQUERADE' | while read rule; do
            iptables -t nat \$(echo \$rule | sed 's/-A/-D/')
        done 2>/dev/null || true

        # Add new DNAT rules
        iptables -t nat -I PREROUTING 1 -p tcp -d $node_ip --dport 80 -j DNAT --to-destination $INGRESS_POD_IP:80
        iptables -t nat -I PREROUTING 1 -p tcp -d $node_ip --dport 443 -j DNAT --to-destination $INGRESS_POD_IP:443

        # Add MASQUERADE for return path
        iptables -t nat -A POSTROUTING -d $INGRESS_POD_IP -p tcp --dport 80 -j MASQUERADE
        iptables -t nat -A POSTROUTING -d $INGRESS_POD_IP -p tcp --dport 443 -j MASQUERADE

        # Save rules
        iptables-save > /etc/sysconfig/iptables

        echo 'Updated successfully'
    " 2>&1
}

# Update all mainnet nodes
update_node $VPS1 "VPS1"
update_node $VPS2 "VPS2"
update_node $VPS3 "VPS3"

echo ""
echo "=== Verification ==="
echo "Testing from VPS4 to each mainnet node..."

for ip in $VPS1 $VPS2 $VPS3; do
    result=$(curl -sk --connect-timeout 5 -H "Host: wallet.gxcoin.money" https://$ip/ 2>&1 | head -1)
    if echo "$result" | grep -q "DOCTYPE\|html"; then
        echo "$ip: ✅ Working"
    else
        echo "$ip: ❌ Failed"
    fi
done

echo ""
echo "Done! All mainnet nodes updated with ingress pod IP: $INGRESS_POD_IP"
