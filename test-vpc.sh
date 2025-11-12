#!/bin/bash
# VPC Complete Test Suite - All 5 Parts + Peering

echo "=========================================="
echo "  VPC Complete Testing Suite"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

PASS=0
FAIL=0

test_it() {
    echo "🧪 TEST: $1"
    if eval "$2" &>/dev/null; then
        echo "   ✅ PASSED"
        ((PASS++))
        return 0
    else
        echo "   ❌ FAILED"
        ((FAIL++))
        return 1
    fi
}

# Cleanup first
echo "🧹 Pre-test cleanup..."
sudo pkill -f "http.server" 2>/dev/null || true
sudo ./vpcctl delete-vpc vpc1 2>/dev/null || true
sudo ./vpcctl delete-vpc vpc2 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
echo ""

# ==========================================
# PART 1: Core VPC Creation
# ==========================================
echo "📦 PART 1: Core VPC Creation"
echo "=========================================="
sudo ./vpcctl create-vpc vpc1 10.0.0.0/16
sudo ./vpcctl add-subnet vpc1 public 10.0.1.0/24
sudo ./vpcctl add-subnet vpc1 private 10.0.2.0/24
echo ""

test_it "VPC bridge exists" "ip link show vpc-vpc1-br"
test_it "Public namespace exists" "ip netns list | grep -q vpc-vpc1-public"
test_it "Private namespace exists" "ip netns list | grep -q vpc-vpc1-private"
test_it "Public has IP assigned" "sudo ip netns exec vpc-vpc1-public ip addr show | grep -q '10.0.1.2'"
test_it "Private has IP assigned" "sudo ip netns exec vpc-vpc1-private ip addr show | grep -q '10.0.2.2'"
echo ""

# ==========================================
# PART 2: Routing and NAT
# ==========================================
echo "🌐 PART 2: Routing and NAT Gateway"
echo "=========================================="
sudo ./vpcctl enable-nat vpc1 10.0.1.0/24 eth0
echo ""

test_it "IP forwarding enabled" "[ \$(cat /proc/sys/net/ipv4/ip_forward) -eq 1 ]"
test_it "NAT rule exists" "sudo iptables -t nat -L | grep -q MASQUERADE"
test_it "Public subnet has internet" "sudo ip netns exec vpc-vpc1-public ping -c 2 -W 5 8.8.8.8"
test_it "Private subnet blocked from internet" "! sudo ip netns exec vpc-vpc1-private ping -c 2 -W 3 8.8.8.8"
test_it "Inter-subnet communication works" "sudo ip netns exec vpc-vpc1-private ping -c 2 -W 3 10.0.1.2"
echo ""

# ==========================================
# PART 3: VPC Isolation & Peering
# ==========================================
echo "🔐 PART 3: VPC Isolation & Peering"
echo "=========================================="

# Create second VPC
sudo ./vpcctl create-vpc vpc2 20.0.0.0/16
sudo ./vpcctl add-subnet vpc2 public 20.0.1.0/24
sudo ./vpcctl enable-nat vpc2 20.0.1.0/24 eth0
echo ""

test_it "VPC2 bridge exists" "ip link show vpc-vpc2-br"
test_it "VPC2 namespace exists" "ip netns list | grep -q vpc-vpc2-public"
test_it "VPCs are isolated (no peering)" "! sudo ip netns exec vpc-vpc2-public ping -c 2 -W 3 10.0.1.2"
echo ""

# Create peering
echo "Creating VPC peering..."
sudo ./vpcctl create-peering vpc1 vpc2
echo ""

test_it "Peering exists" "sudo ./vpcctl list-peering | grep -q 'vpc1<->vpc2'"
test_it "Cross-VPC communication works after peering" "sudo ip netns exec vpc-vpc2-public ping -c 3 -W 5 10.0.1.2"
echo ""

# ==========================================
# PART 4: Security Groups & Firewall
# ==========================================
echo "🛡️  PART 4: Security Groups & Firewall"
echo "=========================================="

# Apply security group rules
sudo ./vpcctl apply-security-group vpc-vpc1-public security-groups.json
echo ""

test_it "Security group applied" "sudo ip netns exec vpc-vpc1-public iptables -L | grep -q 'tcp dpt:80'"
test_it "Port 22 blocked (deny rule)" "sudo ip netns exec vpc-vpc1-public iptables -L | grep -q 'tcp dpt:22'"
echo ""

# ==========================================
# PART 5: Application Deployment
# ==========================================
echo "🚀 PART 5: Application Deployment"
echo "=========================================="

sudo ./vpcctl start-server vpc-vpc1-public 8080
sudo ./vpcctl start-server vpc-vpc1-private 9090
sleep 2
echo ""

test_it "Public web server running" "sudo ip netns exec vpc-vpc1-public curl -s http://localhost:8080 | grep -q 'Hello from'"
test_it "Private web server running" "sudo ip netns exec vpc-vpc1-private curl -s http://localhost:9090 | grep -q 'Hello from'"
test_it "Can access public server from private subnet" "sudo ip netns exec vpc-vpc1-private curl -s http://10.0.1.2:8080 | grep -q 'Hello'"
echo ""

# ==========================================
# PART 6: Describe & Logging
# ==========================================
echo "📋 PART 6: Describe & Logging"
echo "=========================================="

test_it "Describe command works" "sudo ./vpcctl describe vpc1 | grep -q 'VPC: vpc1'"
test_it "Logs file exists and has entries" "[ -f /var/log/vpcctl.log ] && [ -s /var/log/vpcctl.log ]"
test_it "List command shows VPCs" "sudo ./vpcctl list | grep -q 'vpc-vpc1-br'"
echo ""

# ==========================================
# PART 7: Cleanup & Idempotency
# ==========================================
echo "🗑️  PART 7: Cleanup & Idempotency"
echo "=========================================="

# Test idempotency (re-running should not fail)
echo "Testing idempotency..."
sudo ./vpcctl create-vpc vpc1 10.0.0.0/16 2>&1 | grep -q "already exists"
IDEMPOTENT=$?

test_it "Idempotent operations work" "[ $IDEMPOTENT -eq 0 ]"
echo ""

# Cleanup
sudo ./vpcctl stop-server vpc-vpc1-public
sudo ./vpcctl stop-server vpc-vpc1-private
sudo ./vpcctl delete-peering vpc1 vpc2
sudo ./vpcctl delete-vpc vpc1
sudo ./vpcctl delete-vpc vpc2
echo ""

test_it "VPC1 fully deleted" "! ip link show vpc-vpc1-br 2>/dev/null"
test_it "VPC2 fully deleted" "! ip link show vpc-vpc2-br 2>/dev/null"
test_it "No orphaned namespaces" "! ip netns list | grep -q '^vpc-'"
test_it "Peering deleted" "! sudo ./vpcctl list-peering | grep -q 'vpc1<->vpc2'"
echo ""

# ==========================================
# Final Results
# ==========================================
echo "=========================================="
echo "📊 TEST RESULTS"
echo "=========================================="
echo "Total Tests: $((PASS + FAIL))"
echo "✅ Passed: $PASS"
echo "❌ Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED!"
    echo "✅ Project is complete and ready for submission"
    exit 0
else
    echo "⚠️  Some tests failed - review output above"
    exit 1
fi
