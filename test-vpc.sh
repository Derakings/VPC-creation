#!/bin/bash
# VPC Test Script - Tests all 5 parts

echo "=========================================="
echo "  VPC Testing Suite"
echo "  Time: $(date)"
echo "=========================================="
echo ""

PASS=0
FAIL=0

test_it() {
    echo "🧪 $1"
    if eval "$2" &>/dev/null; then
        echo "   ✅ PASSED"
        ((PASS++))
    else
        echo "   ❌ FAILED"
        ((FAIL++))
    fi
}

# Cleanup first
echo "🧹 Cleaning up..."
sudo pkill -f "http.server" 2>/dev/null || true
sudo ./vpcctl delete-vpc vpc1 2>/dev/null || true
sudo ./vpcctl delete-vpc vpc2 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
echo ""

# PART 1
echo "📦 PART 1: Core VPC Creation"
echo "=========================================="
sudo ./vpcctl create-vpc vpc1 10.0.0.0/16
sudo ./vpcctl add-subnet vpc1 public 10.0.1.0/24
sudo ./vpcctl add-subnet vpc1 private 10.0.2.0/24
echo ""
test_it "Bridge exists" "ip link show vpc-vpc1-br"
test_it "Public namespace exists" "ip netns list | grep vpc-vpc1-public"
test_it "Private namespace exists" "ip netns list | grep vpc-vpc1-private"
echo ""

# PART 2
echo "🌐 PART 2: Routing and NAT"
echo "=========================================="
sudo ./vpcctl enable-nat vpc1 10.0.1.0/24
echo ""
test_it "Public has internet" "sudo ip netns exec vpc-vpc1-public ping -c 2 -W 5 8.8.8.8"
test_it "Private blocked from internet" "! sudo ip netns exec vpc-vpc1-private ping -c 2 -W 3 8.8.8.8"
test_it "Subnets can talk" "sudo ip netns exec vpc-vpc1-private ping -c 2 -W 3 10.0.1.2"
echo ""

# PART 3
echo "🚀 PART 3: Applications & Isolation"
echo "=========================================="
sudo ./vpcctl start-server vpc-vpc1-public 8080
sleep 2
sudo ./vpcctl create-vpc vpc2 20.0.0.0/16
sudo ./vpcctl add-subnet vpc2 public 20.0.1.0/24
echo ""
test_it "Web server running" "sudo ip netns exec vpc-vpc1-public curl -s http://localhost:8080 | grep -q Hello"
test_it "VPC2 exists" "ip link show vpc-vpc2-br"
test_it "VPCs isolated" "! sudo ip netns exec vpc-vpc2-public ping -c 2 -W 3 10.0.1.2"
echo ""

# PART 4
echo "🛡️  PART 4: Security Groups"
echo "=========================================="
sudo ip netns exec vpc-vpc1-private iptables -A INPUT -p tcp --dport 22 -j DROP
test_it "Firewall rule applied" "sudo ip netns exec vpc-vpc1-private iptables -L | grep -q 'tcp dpt:22'"
echo ""

# PART 5
echo "🗑️  PART 5: Cleanup"
echo "=========================================="
sudo ./vpcctl stop-server vpc-vpc1-public
sudo ./vpcctl delete-vpc vpc1
sudo ./vpcctl delete-vpc vpc2
test_it "VPC1 deleted" "! ip link show vpc-vpc1-br"
test_it "VPC2 deleted" "! ip link show vpc-vpc2-br"
echo ""

# Results
echo "=========================================="
echo "📊 RESULTS"
echo "=========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""
if [ $FAIL -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED!"
else
    echo "⚠️  Some tests failed"
fi
