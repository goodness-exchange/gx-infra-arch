#!/bin/bash
#===============================================================================
# GX BLOCKCHAIN - COMPREHENSIVE FULL BACKUP SCRIPT
#===============================================================================
# Purpose: Complete backup of all GX infrastructure to Google Drive
# Run on: VPS-1 (72.60.210.201)
# Backs up: K8s resources, Fabric crypto, PostgreSQL, Redis, CouchDB, configs
#===============================================================================

set -e

# FIX: Ensure kubectl and other binaries are in PATH for cron execution
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Configuration
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="gx-full-backup-$BACKUP_DATE"
BACKUP_DIR="/root/backups/temp/$BACKUP_NAME"
LOG_FILE="/root/backup-logs/backup-$BACKUP_DATE.log"
GDRIVE_REMOTE="gdrive-gx"
GDRIVE_PATH="GX-Infrastructure-Backups"

# Server IPs
VPS1="72.60.210.201"
VPS2="72.61.116.210"
VPS3="72.61.81.3"
VPS4="217.196.51.190"
VPS5="195.35.36.174"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Logging function
#-------------------------------------------------------------------------------
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#-------------------------------------------------------------------------------
# Initialize backup
#-------------------------------------------------------------------------------
init_backup() {
    echo "=========================================="
    echo "GX BLOCKCHAIN - FULL BACKUP"
    echo "=========================================="
    echo "Backup ID: $BACKUP_NAME"
    echo "Date: $(date)"
    echo "=========================================="
    echo ""
    
    # Create directories
    mkdir -p "$BACKUP_DIR"/{kubernetes,fabric,databases,docker,configs,audit}
    mkdir -p /root/backup-logs
    
    log INFO "Backup initialized: $BACKUP_NAME"
    log INFO "Backup directory: $BACKUP_DIR"
}

#-------------------------------------------------------------------------------
# Backup Kubernetes Resources
#-------------------------------------------------------------------------------
backup_kubernetes() {
    log INFO "=== Backing up Kubernetes Resources ==="
    
    local K8S_DIR="$BACKUP_DIR/kubernetes"
    
    # Cluster info
    log INFO "Backing up cluster info..."
    kubectl cluster-info dump > "$K8S_DIR/cluster-info.txt" 2>/dev/null || true
    kubectl get nodes -o yaml > "$K8S_DIR/nodes.yaml"
    kubectl get nodes -o wide > "$K8S_DIR/nodes-status.txt"
    
    # All namespaces
    NAMESPACES="fabric fabric-testnet fabric-devnet backend-mainnet backend-testnet backend-devnet monitoring ingress-nginx cert-manager metallb-system registry"
    
    for ns in $NAMESPACES; do
        log INFO "Backing up namespace: $ns"
        mkdir -p "$K8S_DIR/$ns"
        
        # All resources
        kubectl get all -n $ns -o yaml > "$K8S_DIR/$ns/all-resources.yaml" 2>/dev/null || true
        
        # Secrets (critical!)
        kubectl get secrets -n $ns -o yaml > "$K8S_DIR/$ns/secrets.yaml" 2>/dev/null || true
        
        # ConfigMaps
        kubectl get configmaps -n $ns -o yaml > "$K8S_DIR/$ns/configmaps.yaml" 2>/dev/null || true
        
        # PVCs
        kubectl get pvc -n $ns -o yaml > "$K8S_DIR/$ns/pvc.yaml" 2>/dev/null || true
        
        # Services
        kubectl get svc -n $ns -o yaml > "$K8S_DIR/$ns/services.yaml" 2>/dev/null || true
        
        # Deployments
        kubectl get deployments -n $ns -o yaml > "$K8S_DIR/$ns/deployments.yaml" 2>/dev/null || true
        
        # StatefulSets
        kubectl get statefulsets -n $ns -o yaml > "$K8S_DIR/$ns/statefulsets.yaml" 2>/dev/null || true
        
        # Ingress
        kubectl get ingress -n $ns -o yaml > "$K8S_DIR/$ns/ingress.yaml" 2>/dev/null || true
        
        # Network Policies
        kubectl get networkpolicies -n $ns -o yaml > "$K8S_DIR/$ns/networkpolicies.yaml" 2>/dev/null || true
    done
    
    # PVs (cluster-wide)
    kubectl get pv -o yaml > "$K8S_DIR/persistent-volumes.yaml" 2>/dev/null || true
    
    # Storage classes
    kubectl get storageclass -o yaml > "$K8S_DIR/storageclasses.yaml" 2>/dev/null || true
    
    log INFO "✅ Kubernetes backup complete"
}

#-------------------------------------------------------------------------------
# Backup Fabric Crypto Materials
#-------------------------------------------------------------------------------
backup_fabric_crypto() {
    log INFO "=== Backing up Fabric Crypto Materials ==="
    
    local FABRIC_DIR="$BACKUP_DIR/fabric"
    mkdir -p "$FABRIC_DIR"/{secrets,channel-artifacts,chaincode}
    
    # Export all fabric secrets in a recoverable format
    log INFO "Exporting Fabric secrets..."
    
    FABRIC_SECRETS=$(kubectl get secrets -n fabric -o jsonpath='{.items[*].metadata.name}')
    for secret in $FABRIC_SECRETS; do
        log INFO "  Exporting secret: $secret"
        kubectl get secret $secret -n fabric -o yaml > "$FABRIC_DIR/secrets/$secret.yaml" 2>/dev/null || true
        
        # Also export as JSON for easier parsing
        kubectl get secret $secret -n fabric -o json > "$FABRIC_DIR/secrets/$secret.json" 2>/dev/null || true
    done
    
    # Export fabric-testnet secrets
    log INFO "Exporting Fabric TestNet secrets..."
    mkdir -p "$FABRIC_DIR/secrets-testnet"
    TESTNET_SECRETS=$(kubectl get secrets -n fabric-testnet -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    for secret in $TESTNET_SECRETS; do
        kubectl get secret $secret -n fabric-testnet -o yaml > "$FABRIC_DIR/secrets-testnet/$secret.yaml" 2>/dev/null || true
    done
    
    # Channel configuration
    log INFO "Backing up channel configuration..."
    kubectl get configmap -n fabric genesis-block -o yaml > "$FABRIC_DIR/channel-artifacts/genesis-block.yaml" 2>/dev/null || true
    kubectl get configmap -n fabric gxchannel-genesis -o yaml > "$FABRIC_DIR/channel-artifacts/gxchannel-genesis.yaml" 2>/dev/null || true
    
    # CA configurations
    log INFO "Backing up CA configurations..."
    for ca in ca-root ca-tls ca-orderer ca-org1 ca-org2; do
        kubectl get configmap -n fabric ${ca}-config -o yaml > "$FABRIC_DIR/channel-artifacts/${ca}-config.yaml" 2>/dev/null || true
    done
    
    # Backup from Docker containers (VPS-1)
    log INFO "Backing up Docker Fabric volumes..."
    if docker ps 2>/dev/null | grep -q orderer; then
        # Backup orderer data
        for i in 0 1 2 3 4; do
            ORDERER_CONTAINER="orderer${i}.ordererorg.prod.goodness.exchange"
            if docker ps -q -f name=$ORDERER_CONTAINER 2>/dev/null | grep -q .; then
                log INFO "  Backing up $ORDERER_CONTAINER"
                docker cp $ORDERER_CONTAINER:/var/hyperledger/production "$FABRIC_DIR/orderer${i}-production" 2>/dev/null || true
            fi
        done
        
        # Backup peer data
        for org in org1 org2; do
            for peer in 0 1; do
                PEER_CONTAINER="peer${peer}.${org}.prod.goodness.exchange"
                if docker ps -q -f name=$PEER_CONTAINER 2>/dev/null | grep -q .; then
                    log INFO "  Backing up $PEER_CONTAINER"
                    docker cp $PEER_CONTAINER:/var/hyperledger/production "$FABRIC_DIR/peer${peer}-${org}-production" 2>/dev/null || true
                fi
            done
        done
    fi
    
    # Backup crypto from filesystem (if exists)
    if [ -d "/home/sugxcoin/prod-blockchain/gx-coin-fabric/network/organizations" ]; then
        log INFO "Backing up filesystem crypto materials..."
        cp -r /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/organizations "$FABRIC_DIR/" 2>/dev/null || true
    fi
    
    log INFO "✅ Fabric crypto backup complete"
}

#-------------------------------------------------------------------------------
# Backup PostgreSQL
#-------------------------------------------------------------------------------
backup_postgresql() {
    log INFO "=== Backing up PostgreSQL Databases ==="
    
    local DB_DIR="$BACKUP_DIR/databases/postgresql"
    mkdir -p "$DB_DIR"
    
    # MainNet PostgreSQL
    log INFO "Backing up MainNet PostgreSQL..."
    PG_POD=$(kubectl get pods -n backend-mainnet -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$PG_POD" ]; then
        # Full dump
        kubectl exec -n backend-mainnet $PG_POD -- pg_dumpall -U postgres > "$DB_DIR/mainnet-full-dump.sql" 2>/dev/null || true
        
        # Individual databases
        DATABASES=$(kubectl exec -n backend-mainnet $PG_POD -- psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false" 2>/dev/null | tr -d ' ' || echo "")
        for db in $DATABASES; do
            if [ -n "$db" ] && [ "$db" != "postgres" ]; then
                log INFO "  Dumping database: $db"
                kubectl exec -n backend-mainnet $PG_POD -- pg_dump -U postgres -Fc $db > "$DB_DIR/mainnet-$db.dump" 2>/dev/null || true
            fi
        done
        
        log INFO "✅ MainNet PostgreSQL backup complete"
    else
        log WARN "MainNet PostgreSQL pod not found"
    fi
    
    # TestNet PostgreSQL
    log INFO "Backing up TestNet PostgreSQL..."
    PG_POD_TEST=$(kubectl get pods -n backend-testnet -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$PG_POD_TEST" ]; then
        kubectl exec -n backend-testnet $PG_POD_TEST -- pg_dumpall -U postgres > "$DB_DIR/testnet-full-dump.sql" 2>/dev/null || true
        log INFO "✅ TestNet PostgreSQL backup complete"
    else
        log WARN "TestNet PostgreSQL pod not found"
    fi
    
    # Fabric CA PostgreSQL (Docker)
    log INFO "Backing up Fabric CA PostgreSQL..."
    if docker ps 2>/dev/null | grep -q "postgres.ca"; then
        docker exec postgres.ca pg_dumpall -U postgres > "$DB_DIR/fabric-ca-full-dump.sql" 2>/dev/null || true
        log INFO "✅ Fabric CA PostgreSQL backup complete"
    fi
}

#-------------------------------------------------------------------------------
# Backup Redis
#-------------------------------------------------------------------------------
backup_redis() {
    log INFO "=== Backing up Redis ==="

    local REDIS_DIR="$BACKUP_DIR/databases/redis"
    mkdir -p "$REDIS_DIR"

    # MainNet Redis
    log INFO "Backing up MainNet Redis..."
    REDIS_POD=$(kubectl get pods -n backend-mainnet -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$REDIS_POD" ]; then
        # Get Redis password from secret
        REDIS_PASS=$(kubectl get secret -n backend-mainnet redis-credentials -o jsonpath='{.data.REDIS_PASSWORD}' 2>/dev/null | base64 -d || echo "")

        if [ -n "$REDIS_PASS" ]; then
            # Trigger BGSAVE with authentication
            kubectl exec -n backend-mainnet $REDIS_POD -- redis-cli -a "$REDIS_PASS" BGSAVE 2>&1 | grep -v "Warning:" || true
            sleep 5

            # Export all keys as JSON (for inspection)
            kubectl exec -n backend-mainnet $REDIS_POD -- redis-cli -a "$REDIS_PASS" KEYS '*' 2>&1 | grep -v "Warning:" > "$REDIS_DIR/mainnet-keys.txt" || true
        else
            log WARN "Redis password not found, trying without auth..."
            kubectl exec -n backend-mainnet $REDIS_POD -- redis-cli BGSAVE 2>/dev/null || true
            sleep 5
        fi

        # Copy dump.rdb (file-based, no auth needed)
        kubectl cp backend-mainnet/$REDIS_POD:/data/dump.rdb "$REDIS_DIR/mainnet-dump.rdb" 2>/dev/null || true

        log INFO "✅ MainNet Redis backup complete"
    else
        log WARN "MainNet Redis pod not found"
    fi

    # TestNet Redis
    log INFO "Backing up TestNet Redis..."
    REDIS_POD_TEST=$(kubectl get pods -n backend-testnet -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$REDIS_POD_TEST" ]; then
        # Get TestNet Redis password
        REDIS_PASS_TEST=$(kubectl get secret -n backend-testnet redis-credentials -o jsonpath='{.data.REDIS_PASSWORD}' 2>/dev/null | base64 -d || echo "")

        if [ -n "$REDIS_PASS_TEST" ]; then
            kubectl exec -n backend-testnet $REDIS_POD_TEST -- redis-cli -a "$REDIS_PASS_TEST" BGSAVE 2>&1 | grep -v "Warning:" || true
        else
            kubectl exec -n backend-testnet $REDIS_POD_TEST -- redis-cli BGSAVE 2>/dev/null || true
        fi
        sleep 3
        kubectl cp backend-testnet/$REDIS_POD_TEST:/data/dump.rdb "$REDIS_DIR/testnet-dump.rdb" 2>/dev/null || true
        log INFO "✅ TestNet Redis backup complete"
    fi
}

#-------------------------------------------------------------------------------
# Backup CouchDB
#-------------------------------------------------------------------------------
backup_couchdb() {
    log INFO "=== Backing up CouchDB State Databases ==="

    local COUCH_DIR="$BACKUP_DIR/databases/couchdb"
    mkdir -p "$COUCH_DIR"

    # CouchDB credentials (same for all Fabric CouchDB instances)
    local COUCH_USER="admin"
    local COUCH_PASS="adminpw"

    # Get all CouchDB pods
    COUCHDB_PODS=$(kubectl get pods -n fabric -l app=couchdb -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    for pod in $COUCHDB_PODS; do
        log INFO "Backing up CouchDB: $pod"
        mkdir -p "$COUCH_DIR/$pod"

        # Get list of databases with authentication
        DBS=$(kubectl exec -n fabric $pod -- curl -s -u "${COUCH_USER}:${COUCH_PASS}" http://localhost:5984/_all_dbs 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

        if [ -z "$DBS" ]; then
            log WARN "  No databases found or auth failed, using tar backup..."
            # Fallback: backup data directory via tar
            kubectl exec -n fabric $pod -- tar -cf - /opt/couchdb/data 2>/dev/null | gzip > "$COUCH_DIR/$pod.tar.gz" || true
        else
            for db in $DBS; do
                # Skip system databases for backup (they're recreated)
                if [[ "$db" != "_"* ]]; then
                    log INFO "  Exporting database: $db"
                    kubectl exec -n fabric $pod -- curl -s -u "${COUCH_USER}:${COUCH_PASS}" "http://localhost:5984/$db/_all_docs?include_docs=true" > "$COUCH_DIR/$pod/$db.json" 2>/dev/null || true
                fi
            done
        fi
    done

    # Backup Docker CouchDB (if exists)
    log INFO "Backing up Docker CouchDB instances..."
    for i in 0 1 2 3; do
        COUCH_CONTAINER="couchdb${i}"
        if docker ps -q -f name=$COUCH_CONTAINER 2>/dev/null | grep -q .; then
            log INFO "  Backing up $COUCH_CONTAINER"
            mkdir -p "$COUCH_DIR/docker-$COUCH_CONTAINER"

            PORT=$((5984 + i * 1000))
            DBS=$(curl -s -u "${COUCH_USER}:${COUCH_PASS}" http://localhost:$PORT/_all_dbs 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

            for db in $DBS; do
                if [[ "$db" != "_"* ]]; then
                    curl -s -u "${COUCH_USER}:${COUCH_PASS}" "http://localhost:$PORT/$db/_all_docs?include_docs=true" > "$COUCH_DIR/docker-$COUCH_CONTAINER/$db.json" 2>/dev/null || true
                fi
            done
        fi
    done

    log INFO "✅ CouchDB backup complete"
}

#-------------------------------------------------------------------------------
# Backup Docker Volumes and Compose Files
#-------------------------------------------------------------------------------
backup_docker() {
    log INFO "=== Backing up Docker Volumes and Configs ==="
    
    local DOCKER_DIR="$BACKUP_DIR/docker"
    mkdir -p "$DOCKER_DIR"/{volumes,compose}
    
    # List all volumes
    docker volume ls > "$DOCKER_DIR/volume-list.txt" 2>/dev/null || true
    
    # Backup docker-compose files
    if [ -d "/home/sugxcoin/prod-blockchain/gx-coin-fabric/network" ]; then
        log INFO "Backing up docker-compose files..."
        cp /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/*.yaml "$DOCKER_DIR/compose/" 2>/dev/null || true
        cp /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/*.yml "$DOCKER_DIR/compose/" 2>/dev/null || true
        cp /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/.env "$DOCKER_DIR/compose/" 2>/dev/null || true
    fi
    
    # Backup critical volumes (this can be large)
    log INFO "Backing up critical Docker volumes..."
    CRITICAL_VOLUMES=$(docker volume ls -q 2>/dev/null | grep -E "orderer|peer|ca|couchdb" || echo "")
    
    for vol in $CRITICAL_VOLUMES; do
        log INFO "  Backing up volume: $vol"
        docker run --rm -v $vol:/source -v "$DOCKER_DIR/volumes":/backup alpine \
            tar -czf /backup/${vol}.tar.gz -C /source . 2>/dev/null || true
    done
    
    log INFO "✅ Docker backup complete"
}

#-------------------------------------------------------------------------------
# Backup Application Configs
#-------------------------------------------------------------------------------
backup_configs() {
    log INFO "=== Backing up Application Configurations ==="
    
    local CONFIG_DIR="$BACKUP_DIR/configs"
    mkdir -p "$CONFIG_DIR"/{backend,frontend,fabric,system}
    
    # Backend configs
    if [ -f "/home/sugxcoin/prod-blockchain/gx-protocol-backend/.env" ]; then
        cp /home/sugxcoin/prod-blockchain/gx-protocol-backend/.env "$CONFIG_DIR/backend/" 2>/dev/null || true
    fi
    if [ -f "/home/sugxcoin/prod-blockchain/gx-protocol-backend/.env.production" ]; then
        cp /home/sugxcoin/prod-blockchain/gx-protocol-backend/.env.production "$CONFIG_DIR/backend/" 2>/dev/null || true
    fi
    
    # Frontend configs
    if [ -f "/home/sugxcoin/prod-blockchain/gx-wallet-frontend/.env.local" ]; then
        cp /home/sugxcoin/prod-blockchain/gx-wallet-frontend/.env.local "$CONFIG_DIR/frontend/" 2>/dev/null || true
    fi
    if [ -f "/home/sugxcoin/prod-blockchain/gx-wallet-frontend/.env.production" ]; then
        cp /home/sugxcoin/prod-blockchain/gx-wallet-frontend/.env.production "$CONFIG_DIR/frontend/" 2>/dev/null || true
    fi
    
    # Fabric configs
    if [ -d "/home/sugxcoin/prod-blockchain/gx-coin-fabric/network/configtx" ]; then
        cp -r /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/configtx "$CONFIG_DIR/fabric/" 2>/dev/null || true
    fi
    
    # System configs
    cp /etc/hosts "$CONFIG_DIR/system/" 2>/dev/null || true
    crontab -l > "$CONFIG_DIR/system/crontab.txt" 2>/dev/null || true
    
    # K3s config
    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        cp /etc/rancher/k3s/k3s.yaml "$CONFIG_DIR/system/" 2>/dev/null || true
    fi
    
    log INFO "✅ Configuration backup complete"
}

#-------------------------------------------------------------------------------
# Backup Audit Files
#-------------------------------------------------------------------------------
backup_audit_files() {
    log INFO "=== Backing up Audit Files ==="
    
    local AUDIT_DIR="$BACKUP_DIR/audit"
    
    # Copy any existing audit files
    if ls /root/infrastructure-audit-*.tar.gz 1>/dev/null 2>&1; then
        cp /root/infrastructure-audit-*.tar.gz "$AUDIT_DIR/" 2>/dev/null || true
    fi
    
    # Create current system state snapshot
    log INFO "Creating current system state snapshot..."
    
    # Node info
    kubectl get nodes -o wide > "$AUDIT_DIR/current-nodes.txt" 2>/dev/null || true
    kubectl top nodes > "$AUDIT_DIR/current-node-resources.txt" 2>/dev/null || true
    
    # Pod info
    kubectl get pods -A -o wide > "$AUDIT_DIR/current-pods.txt" 2>/dev/null || true
    kubectl top pods -A > "$AUDIT_DIR/current-pod-resources.txt" 2>/dev/null || true
    
    # Services
    kubectl get svc -A > "$AUDIT_DIR/current-services.txt" 2>/dev/null || true
    
    # Disk usage
    df -h > "$AUDIT_DIR/disk-usage.txt" 2>/dev/null || true
    
    # Memory/CPU
    free -h > "$AUDIT_DIR/memory-usage.txt" 2>/dev/null || true
    
    log INFO "✅ Audit backup complete"
}

#-------------------------------------------------------------------------------
# Create Archive and Upload to Google Drive
#-------------------------------------------------------------------------------
create_and_upload() {
    log INFO "=== Creating Archive and Uploading to Google Drive ==="
    
    # Create manifest
    log INFO "Creating backup manifest..."
    cat > "$BACKUP_DIR/MANIFEST.txt" << EOF
GX BLOCKCHAIN FULL BACKUP
=========================
Backup ID: $BACKUP_NAME
Created: $(date)
Server: $(hostname)
Server IP: $(hostname -I | awk '{print $1}')

Contents:
- kubernetes/    : All K8s resources (secrets, configs, deployments)
- fabric/        : Fabric crypto materials and channel configs
- databases/     : PostgreSQL, Redis, CouchDB backups
- docker/        : Docker volumes and compose files
- configs/       : Application configuration files
- audit/         : System audit snapshots

Namespaces Backed Up:
- fabric
- fabric-testnet
- fabric-devnet
- backend-mainnet
- backend-testnet
- monitoring
- ingress-nginx
- cert-manager

Restore Instructions:
1. Extract archive: tar -xzvf $BACKUP_NAME.tar.gz
2. Apply K8s resources: kubectl apply -f kubernetes/
3. Restore databases from dumps
4. Restore Docker volumes if needed

EOF
    
    # Create archive
    log INFO "Creating compressed archive..."
    cd /root/backups/temp
    tar -czvf "/root/backups/$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
    
    ARCHIVE_SIZE=$(du -h "/root/backups/$BACKUP_NAME.tar.gz" | cut -f1)
    log INFO "Archive created: $BACKUP_NAME.tar.gz ($ARCHIVE_SIZE)"
    
    # Upload to Google Drive
    log INFO "Uploading to Google Drive..."
    
    # Determine destination folder based on backup type
    DEST_FOLDER="manual"
    if [ "$1" == "daily" ]; then
        DEST_FOLDER="daily"
    elif [ "$1" == "weekly" ]; then
        DEST_FOLDER="weekly"
    elif [ "$1" == "monthly" ]; then
        DEST_FOLDER="monthly"
    elif [ "$1" == "pre-migration" ]; then
        DEST_FOLDER="pre-migration"
    fi
    
    if rclone copy "/root/backups/$BACKUP_NAME.tar.gz" "$GDRIVE_REMOTE:$GDRIVE_PATH/$DEST_FOLDER/" --progress; then
        log INFO "✅ Upload successful to: $GDRIVE_PATH/$DEST_FOLDER/"
        
        # Verify upload
        if rclone ls "$GDRIVE_REMOTE:$GDRIVE_PATH/$DEST_FOLDER/$BACKUP_NAME.tar.gz" 2>/dev/null; then
            log INFO "✅ Upload verified in Google Drive"
        fi
    else
        log ERROR "Upload failed!"
        return 1
    fi
    
    # Cleanup temp directory
    rm -rf "$BACKUP_DIR"
    
    log INFO "Backup archive stored locally at: /root/backups/$BACKUP_NAME.tar.gz"
}

#-------------------------------------------------------------------------------
# Cleanup old backups
#-------------------------------------------------------------------------------
cleanup_old_backups() {
    log INFO "=== Cleaning up old backups ==="
    
    # Local cleanup - keep last 5 backups
    cd /root/backups
    ls -t gx-full-backup-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
    
    # Google Drive cleanup - keep last 7 daily backups
    rclone delete "$GDRIVE_REMOTE:$GDRIVE_PATH/daily/" --min-age 7d 2>/dev/null || true
    
    # Keep last 4 weekly backups
    rclone delete "$GDRIVE_REMOTE:$GDRIVE_PATH/weekly/" --min-age 28d 2>/dev/null || true
    
    # Keep last 12 monthly backups
    rclone delete "$GDRIVE_REMOTE:$GDRIVE_PATH/monthly/" --min-age 365d 2>/dev/null || true
    
    log INFO "✅ Cleanup complete"
}

#-------------------------------------------------------------------------------
# Main execution
#-------------------------------------------------------------------------------
main() {
    local BACKUP_TYPE=${1:-"manual"}
    
    init_backup
    
    # Run all backup functions
    backup_kubernetes
    backup_fabric_crypto
    backup_postgresql
    backup_redis
    backup_couchdb
    backup_docker
    backup_configs
    backup_audit_files
    
    # Create archive and upload
    create_and_upload "$BACKUP_TYPE"
    
    # Cleanup if automated
    if [ "$BACKUP_TYPE" != "manual" ] && [ "$BACKUP_TYPE" != "pre-migration" ]; then
        cleanup_old_backups
    fi
    
    echo ""
    echo "=========================================="
    echo "BACKUP COMPLETE!"
    echo "=========================================="
    echo ""
    echo "Backup ID: $BACKUP_NAME"
    echo "Local: /root/backups/$BACKUP_NAME.tar.gz"
    echo "Google Drive: $GDRIVE_PATH/$BACKUP_TYPE/"
    echo "Log: $LOG_FILE"
    echo ""
    echo "To list backups in Google Drive:"
    echo "  rclone ls $GDRIVE_REMOTE:$GDRIVE_PATH/"
    echo ""
}

# Show usage
usage() {
    echo "Usage: $0 [backup-type]"
    echo ""
    echo "Backup types:"
    echo "  manual        - Manual backup (default)"
    echo "  daily         - Daily automated backup"
    echo "  weekly        - Weekly automated backup"
    echo "  monthly       - Monthly automated backup"
    echo "  pre-migration - Pre-migration backup (permanent)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Manual backup"
    echo "  $0 pre-migration    # Pre-migration backup"
    echo "  $0 daily            # Daily backup (with cleanup)"
}

# Parse arguments
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
    exit 0
fi

# Run main
main "$1"
