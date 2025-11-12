#!/bin/bash
# Quick Demo Script

echo "======================================"
echo "VPC Demo - DevOps Stage 4"
echo "======================================"
echo ""

echo "Step 1: Create VPC"
sudo ./vpcctl create-vpc demo 10.0.0.0/16
echo ""

echo "Step 2: Add Subnets"
sudo ./vpcctl add-subnet demo public 10.0.1.0/24
sudo ./vpcctl add-subnet demo private 10.0.2.0/24
echo ""

echo "Step 3: Enable NAT"
sudo ./vpcctl enable-nat demo 10.0.1.0/24
echo ""

echo "Step 4: Test Connectivity"
echo "Public subnet (should work):"
sudo ip netns exec vpc-demo-public ping -c 3 8.8.8.8
echo ""
echo "Private subnet (should fail):"
sudo ip netns exec vpc-demo-private ping -c 2 -W 2 8.8.8.8 || echo "✓ Correctly blocked!"
echo ""

echo "Step 5: Deploy Web Server"
sudo ./vpcctl start-server vpc-demo-public 8080
sleep 2
sudo ip netns exec vpc-demo-public curl http://localhost:8080
echo ""

echo "Step 6: List VPCs"
sudo ./vpcctl list
echo ""

read -p "Press Enter to cleanup..."
sudo ./vpcctl stop-server vpc-demo-public
sudo ./vpcctl delete-vpc demo
echo "✅ Done!"
