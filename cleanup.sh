#!/bin/bash
# Complete Cleanup

echo " Cleaning ALL VPC resources..."

sudo pkill -f "http.server" 2>/dev/null || true

for ns in $(sudo ip netns list | grep "^vpc-" | awk '{print $1}'); do
    echo "  Deleting: $ns"
    sudo ip netns del "$ns" 2>/dev/null
done

for br in $(ip link show type bridge | grep "vpc-" | awk '{print $2}' | tr -d ':'); do
    echo "  Deleting bridge: $br"
    sudo ip link set "$br" down 2>/dev/null
    sudo ip link del "$br" 2>/dev/null
done

sudo iptables -t nat -F 2>/dev/null
sudo iptables -F FORWARD 2>/dev/null
rm -rf /tmp/vpc-web-* 2>/dev/null

echo "✅ Cleanup complete!"
