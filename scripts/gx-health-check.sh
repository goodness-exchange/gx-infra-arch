#!/bin/bash
#
# GX Protocol Infrastructure Health Check Script
# Version: 1.0.0
# Date: 2025-12-20
#
# Usage: ./gx-health-check.sh [options]
#   Options:
#     --full      Run full health check (default)
#     --quick     Run quick health check (cluster + pods only)
#     --services  Check services health only
#     --db        Check databases only
#     --fabric    Check Hyperledger Fabric only
#     --help      Show this help message
#
# This script checks:
#   - Kubernetes cluster nodes
#   - Pod status across all namespaces
#   - Database health (PostgreSQL, Redis, CouchDB)
#   - Hyperledger Fabric network
#   - Service endpoints and health
#   - Inter-service communication
#   - Monitoring stack
#   - Storage (PVCs)
#   - External API access
#

# Don't exit on errors - we handle them ourselves
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}─── $1 ───${NC}"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
}

# ============================================================================
# CLUSTER HEALTH CHECKS
# ============================================================================

check_cluster_nodes() {
    print_section "Kubernetes Cluster Nodes"

    local nodes=$(kubectl get nodes --no-headers 2>/dev/null)
    local node_count=$(echo "$nodes" | wc -l | tr -d ' ')
    local ready_count=$(echo "$nodes" | grep -c "Ready" 2>/dev/null || echo "0")

    echo "  Nodes: $ready_count/$node_count Ready"
    echo ""

    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local role=$(echo "$line" | awk '{print $3}')
        local version=$(echo "$line" | awk '{print $5}')

        if [[ "$status" == "Ready" ]]; then
            print_pass "$name ($role) - $version"
        else
            print_fail "$name ($role) - Status: $status"
        fi
    done <<< "$nodes"

    if [[ $ready_count -eq $node_count ]]; then
        print_pass "All $node_count nodes are Ready"
    else
        print_fail "Only $ready_count of $node_count nodes are Ready"
    fi
}

check_node_resources() {
    print_section "Node Resources"

    local resources=$(kubectl top nodes 2>/dev/null)
    if [[ -z "$resources" ]]; then
        print_warn "Metrics server not available"
        return
    fi

    echo "$resources" | tail -n +2 | while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local cpu=$(echo "$line" | awk '{print $3}' | tr -d '%')
        local mem=$(echo "$line" | awk '{print $5}' | tr -d '%')

        local status="OK"
        if [[ $cpu -gt 80 ]] || [[ $mem -gt 80 ]]; then
            status="HIGH"
            print_warn "$name - CPU: ${cpu}% | Memory: ${mem}%"
        else
            print_pass "$name - CPU: ${cpu}% | Memory: ${mem}%"
        fi
    done
}

# ============================================================================
# POD STATUS CHECKS
# ============================================================================

check_pods_by_namespace() {
    print_section "Pod Status by Namespace"

    local namespaces="backend-mainnet backend-testnet backend-devnet fabric fabric-testnet fabric-devnet monitoring ingress-nginx registry kube-system"

    for ns in $namespaces; do
        local pods=$(kubectl get pods -n $ns --no-headers 2>/dev/null)
        if [[ -z "$pods" ]]; then
            continue
        fi

        local total
        local running
        local completed
        total=$(echo "$pods" | wc -l | tr -d '[:space:]')
        running=$(echo "$pods" | grep -c "Running" 2>/dev/null) || running=0
        completed=$(echo "$pods" | grep -c "Completed" 2>/dev/null) || completed=0
        # Ensure numeric values
        total=$((total + 0))
        running=$((running + 0))
        completed=$((completed + 0))
        local healthy=$((running + completed))
        local unhealthy=$((total - healthy))

        if [[ $unhealthy -eq 0 ]]; then
            print_pass "$ns: $total pods ($running Running, $completed Completed)"
        else
            print_fail "$ns: $unhealthy unhealthy pods out of $total"
        fi
    done
}

check_unhealthy_pods() {
    print_section "Unhealthy Pods Check"

    local unhealthy=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v -E "Running|Completed")

    if [[ -z "$unhealthy" ]]; then
        print_pass "No unhealthy pods found"
    else
        print_fail "Unhealthy pods detected:"
        echo "$unhealthy" | while IFS= read -r line; do
            echo "    $line"
        done
    fi
}

# ============================================================================
# DATABASE HEALTH CHECKS
# ============================================================================

check_postgresql() {
    print_section "PostgreSQL Health"

    local envs="backend-mainnet backend-testnet backend-devnet"

    for env in $envs; do
        local result
        result=$(kubectl exec -n $env postgres-0 -- psql -U gx_admin -d gx_protocol -c "SELECT 'OK' as status;" 2>/dev/null | grep -c "OK" 2>/dev/null) || result=0
        result=$((result + 0))

        if [[ $result -gt 0 ]]; then
            print_pass "$env: PostgreSQL responding"
        else
            print_fail "$env: PostgreSQL not responding"
        fi
    done

    # Check MainNet replication
    print_info "MainNet Replication Status:"
    local replication=$(kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null | grep -oE '[0-9]+' | head -1)

    if [[ "$replication" -ge 2 ]]; then
        print_pass "MainNet: $replication replicas streaming"
    elif [[ "$replication" -ge 1 ]]; then
        print_warn "MainNet: Only $replication replica streaming"
    else
        print_fail "MainNet: No replication detected"
    fi
}

check_redis() {
    print_section "Redis Health"

    local envs="backend-mainnet backend-testnet backend-devnet"

    for env in $envs; do
        local result
        local redis_password=""

        # Try to get password from various secret locations
        # MainNet uses redis-credentials, TestNet/DevNet use redis-secret
        redis_password=$(kubectl get secret -n $env redis-credentials -o jsonpath='{.data.REDIS_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null)
        if [[ -z "$redis_password" ]]; then
            redis_password=$(kubectl get secret -n $env redis-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
        fi
        if [[ -z "$redis_password" ]]; then
            redis_password=$(kubectl get secret -n $env redis-secret -o jsonpath='{.data.REDIS_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null)
        fi

        # Try with auth first (all environments use auth)
        if [[ -n "$redis_password" ]]; then
            # Use REDISCLI_AUTH env var to avoid shell escaping issues with special chars
            # Escape single quotes in password by replacing ' with '\''
            local escaped_password="${redis_password//\'/\'\\\'\'}"
            local ping_result
            ping_result=$(kubectl exec -n $env redis-0 -- sh -c "export REDISCLI_AUTH='$escaped_password' && redis-cli ping" 2>&1)
            if [[ "$ping_result" == *"PONG"* ]]; then
                print_pass "$env: Redis responding (with auth)"
                continue
            fi
        fi

        # Fallback: Try without auth
        result=$(kubectl exec -n $env redis-0 -- redis-cli ping 2>/dev/null | grep -c "PONG" 2>/dev/null) || result=0
        result=$((result + 0))

        if [[ $result -gt 0 ]]; then
            print_pass "$env: Redis responding"
        else
            print_fail "$env: Redis not responding"
        fi
    done
}

check_couchdb() {
    print_section "CouchDB Health (Fabric)"

    local pods="couchdb-peer0-org1-0 couchdb-peer0-org2-0 couchdb-peer1-org1-0 couchdb-peer1-org2-0"

    for pod in $pods; do
        local result
        result=$(kubectl exec -n fabric $pod -- curl -s http://admin:adminpw@localhost:5984/ 2>/dev/null | grep -c "Welcome" 2>/dev/null) || result=0
        result=$((result + 0))

        if [[ $result -gt 0 ]]; then
            print_pass "$pod: CouchDB responding"
        else
            print_fail "$pod: CouchDB not responding"
        fi
    done
}

# ============================================================================
# HYPERLEDGER FABRIC CHECKS
# ============================================================================

check_fabric_network() {
    print_section "Hyperledger Fabric Network"

    # Check orderers
    local orderers=$(kubectl get pods -n fabric -l app=orderer --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
    orderers=${orderers:-0}
    if [[ $orderers -ge 5 ]]; then
        print_pass "Orderers: $orderers/5 Running"
    else
        print_fail "Orderers: Only $orderers/5 Running"
    fi

    # Check peers
    local peers=$(kubectl get pods -n fabric --no-headers 2>/dev/null | grep "peer.*Running" | wc -l | tr -d ' ')
    peers=${peers:-0}
    if [[ $peers -ge 4 ]]; then
        print_pass "Peers: $peers/4 Running"
    else
        print_fail "Peers: Only $peers/4 Running"
    fi

    # Check channel
    local channel=$(kubectl exec -n fabric peer0-org1-0 -- peer channel list 2>&1 | grep -c "gxchannel" 2>/dev/null || echo "0")
    channel=${channel:-0}
    if [[ $channel -gt 0 ]]; then
        print_pass "Channel: gxchannel joined"
    else
        print_fail "Channel: gxchannel not found"
    fi

    # Check block height
    local height=$(kubectl exec -n fabric peer0-org1-0 -- peer channel getinfo -c gxchannel 2>&1 | grep -oP '"height":\K[0-9]+' 2>/dev/null || echo "0")
    height=${height:-0}
    if [[ $height -gt 0 ]]; then
        print_pass "Block Height: $height"
    else
        print_warn "Could not retrieve block height"
    fi

    # Check chaincode
    local chaincode=$(kubectl get pods -n fabric --no-headers 2>/dev/null | grep -c "chaincode.*Running" 2>/dev/null || echo "0")
    chaincode=${chaincode:-0}
    if [[ $chaincode -gt 0 ]]; then
        print_pass "Chaincode: $chaincode instance(s) running"
    else
        print_fail "Chaincode: No instances running"
    fi
}

# ============================================================================
# SERVICE HEALTH CHECKS
# ============================================================================

check_service_health() {
    print_section "Service Health (MainNet)"

    # Container ports (used for localhost checks inside the container)
    local services="svc-admin:3006 svc-identity:3001 svc-tokenomics:3002"

    for svc in $services; do
        local name=$(echo $svc | cut -d: -f1)
        local port=$(echo $svc | cut -d: -f2)

        local health
        health=$(kubectl exec -n backend-mainnet deploy/$name -- wget -qO- http://localhost:$port/health 2>/dev/null | grep -c '"status":"ok"' 2>/dev/null) || health=0
        health=$((health + 0))

        if [[ $health -gt 0 ]]; then
            print_pass "$name: Healthy"
        else
            print_fail "$name: Not responding"
        fi
    done
}

check_service_endpoints() {
    print_section "Service Endpoints (MainNet)"

    local services="svc-admin svc-identity svc-tokenomics postgres redis"

    for svc in $services; do
        local endpoints=$(kubectl get endpoints -n backend-mainnet $svc --no-headers 2>/dev/null | awk '{print $2}')

        if [[ "$endpoints" != "<none>" ]] && [[ -n "$endpoints" ]]; then
            local count=$(echo "$endpoints" | tr ',' '\n' | wc -l)
            print_pass "$svc: $count endpoint(s)"
        else
            print_fail "$svc: No endpoints"
        fi
    done
}

check_inter_service_communication() {
    print_section "Inter-Service Communication"

    # Test svc-admin can reach svc-identity
    local result
    result=$(kubectl exec -n backend-mainnet deploy/svc-admin -- wget -qO- http://svc-identity:3001/health 2>/dev/null | grep -c '"status":"ok"' 2>/dev/null) || result=0
    result=$((result + 0))

    if [[ $result -gt 0 ]]; then
        print_pass "svc-admin → svc-identity: OK"
    else
        print_fail "svc-admin → svc-identity: FAILED"
    fi

    # Test svc-admin can reach svc-tokenomics (service port is 3003)
    result=$(kubectl exec -n backend-mainnet deploy/svc-admin -- wget -qO- http://svc-tokenomics:3003/health 2>/dev/null | grep -c '"status":"ok"' 2>/dev/null) || result=0
    result=$((result + 0))

    if [[ $result -gt 0 ]]; then
        print_pass "svc-admin → svc-tokenomics: OK"
    else
        print_fail "svc-admin → svc-tokenomics: FAILED"
    fi
}

check_external_api() {
    print_section "External API Access"

    local health
    health=$(curl -sk https://api.gxcoin.money/health 2>/dev/null | grep -c '"status":"ok"' 2>/dev/null) || health=0
    health=$((health + 0))

    if [[ $health -gt 0 ]]; then
        print_pass "api.gxcoin.money: Accessible"
    else
        print_fail "api.gxcoin.money: Not accessible"
    fi
}

# ============================================================================
# MONITORING STACK CHECKS
# ============================================================================

check_monitoring_stack() {
    print_section "Monitoring Stack"

    local components="prometheus alertmanager grafana loki"

    for comp in $components; do
        local running=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c "$comp.*Running" 2>/dev/null || echo "0")
        running=${running:-0}
        if [[ $running -gt 0 ]]; then
            print_pass "$comp: Running"
        else
            print_fail "$comp: Not running"
        fi
    done

    # Check node exporters
    local exporters=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c "node-exporter.*Running" 2>/dev/null || echo "0")
    exporters=${exporters:-0}
    print_pass "Node Exporters: $exporters running"

    # Check promtail
    local promtail=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c "promtail.*Running" 2>/dev/null || echo "0")
    promtail=${promtail:-0}
    print_pass "Promtail: $promtail running"
}

# ============================================================================
# STORAGE CHECKS
# ============================================================================

check_storage() {
    print_section "Storage (PVCs)"

    local pvcs=$(kubectl get pvc -A --no-headers 2>/dev/null)
    local total=$(echo "$pvcs" | wc -l | tr -d ' ')
    local bound=$(echo "$pvcs" | grep -c "Bound" 2>/dev/null || echo "0")
    bound=${bound:-0}

    if [[ $bound -eq $total ]]; then
        print_pass "All $total PVCs are Bound"
    else
        print_fail "Only $bound of $total PVCs are Bound"
        echo "$pvcs" | grep -v "Bound" | while IFS= read -r line; do
            echo "    $line"
        done
    fi
}

# ============================================================================
# INGRESS CHECKS
# ============================================================================

check_ingress() {
    print_section "Ingress & Certificates"

    # Check ingress controller
    local ingress=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
    ingress=${ingress:-0}
    if [[ $ingress -gt 0 ]]; then
        print_pass "Ingress Controller: Running"
    else
        print_fail "Ingress Controller: Not running"
    fi

    # Check certificates
    local certs=$(kubectl get certificates -A --no-headers 2>/dev/null)
    if [[ -n "$certs" ]]; then
        echo "$certs" | while IFS= read -r line; do
            local name=$(echo "$line" | awk '{print $2}')
            local ready=$(echo "$line" | awk '{print $3}')
            if [[ "$ready" == "True" ]]; then
                print_pass "Certificate $name: Valid"
            else
                print_fail "Certificate $name: Not ready"
            fi
        done
    fi
}

# ============================================================================
# DNS CHECKS
# ============================================================================

check_dns() {
    print_section "DNS Resolution"

    local coredns=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
    coredns=${coredns:-0}
    if [[ $coredns -gt 0 ]]; then
        print_pass "CoreDNS: $coredns instance(s) running"
    else
        print_fail "CoreDNS: Not running"
    fi

    # Test internal DNS
    local dns_test=$(kubectl exec -n backend-mainnet deploy/svc-admin -- nslookup svc-identity.backend-mainnet.svc.cluster.local 2>/dev/null | grep -c "Address:" 2>/dev/null || echo "0")
    dns_test=${dns_test:-0}
    if [[ $dns_test -gt 1 ]]; then
        print_pass "Internal DNS: Resolving"
    else
        print_fail "Internal DNS: Not resolving"
    fi
}

# ============================================================================
# DEVNET/TESTNET HEALTH
# ============================================================================

check_other_environments() {
    print_section "DevNet & TestNet Health"

    for env in backend-devnet backend-testnet; do
        local name=$(echo $env | cut -d- -f2)
        local health
        health=$(kubectl exec -n $env deploy/svc-admin -- wget -qO- http://localhost:3006/health 2>/dev/null | grep -c '"status":"ok"' 2>/dev/null) || health=0
        health=$((health + 0))

        if [[ $health -gt 0 ]]; then
            print_pass "$name svc-admin: Healthy"
        else
            print_fail "$name svc-admin: Not responding"
        fi
    done
}

# ============================================================================
# SUMMARY
# ============================================================================

print_summary() {
    print_header "HEALTH CHECK SUMMARY"

    local total=$((PASSED + FAILED + WARNINGS))

    echo ""
    echo -e "  ${GREEN}Passed:${NC}   $PASSED"
    echo -e "  ${RED}Failed:${NC}   $FAILED"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "  ${BLUE}Total:${NC}    $total"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║           ALL SYSTEMS OPERATIONAL                             ║${NC}"
        echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}║           $FAILED ISSUE(S) DETECTED - REVIEW REQUIRED              ║${NC}"
        echo -e "${RED}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    fi

    echo ""
    echo "Health check completed at $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

# ============================================================================
# MAIN
# ============================================================================

show_help() {
    echo "GX Protocol Infrastructure Health Check"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --full      Run full health check (default)"
    echo "  --quick     Run quick health check (cluster + pods only)"
    echo "  --services  Check services health only"
    echo "  --db        Check databases only"
    echo "  --fabric    Check Hyperledger Fabric only"
    echo "  --help      Show this help message"
    echo ""
}

run_full_check() {
    print_header "GX PROTOCOL INFRASTRUCTURE HEALTH CHECK"
    echo "Started at $(date '+%Y-%m-%d %H:%M:%S %Z')"

    check_kubectl
    check_cluster_nodes
    check_node_resources
    check_pods_by_namespace
    check_unhealthy_pods
    check_postgresql
    check_redis
    check_couchdb
    check_fabric_network
    check_service_health
    check_service_endpoints
    check_inter_service_communication
    check_external_api
    check_monitoring_stack
    check_storage
    check_ingress
    check_dns
    check_other_environments

    print_summary
}

run_quick_check() {
    print_header "GX PROTOCOL QUICK HEALTH CHECK"
    echo "Started at $(date '+%Y-%m-%d %H:%M:%S %Z')"

    check_kubectl
    check_cluster_nodes
    check_pods_by_namespace
    check_unhealthy_pods

    print_summary
}

run_services_check() {
    print_header "GX PROTOCOL SERVICES HEALTH CHECK"
    echo "Started at $(date '+%Y-%m-%d %H:%M:%S %Z')"

    check_kubectl
    check_service_health
    check_service_endpoints
    check_inter_service_communication
    check_external_api
    check_other_environments

    print_summary
}

run_db_check() {
    print_header "GX PROTOCOL DATABASE HEALTH CHECK"
    echo "Started at $(date '+%Y-%m-%d %H:%M:%S %Z')"

    check_kubectl
    check_postgresql
    check_redis
    check_couchdb

    print_summary
}

run_fabric_check() {
    print_header "GX PROTOCOL FABRIC HEALTH CHECK"
    echo "Started at $(date '+%Y-%m-%d %H:%M:%S %Z')"

    check_kubectl
    check_fabric_network
    check_couchdb

    print_summary
}

# Parse arguments
case "${1:-}" in
    --help)
        show_help
        exit 0
        ;;
    --quick)
        run_quick_check
        ;;
    --services)
        run_services_check
        ;;
    --db)
        run_db_check
        ;;
    --fabric)
        run_fabric_check
        ;;
    --full|"")
        run_full_check
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

# Exit with appropriate code
if [[ $FAILED -gt 0 ]]; then
    exit 1
else
    exit 0
fi
