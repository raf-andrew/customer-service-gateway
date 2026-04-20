#!/bin/bash
# backup.sh - Backup database and gateway configuration
# Usage: bash scripts/backup.sh
# Creates timestamped backup files in ./backups/

set -e

BACKUP_DIR="../webapp_core/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_BACKUP="$BACKUP_DIR/webapp_core_$TIMESTAMP.sql.gz"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Backup Starting"
echo "  Timestamp: $TIMESTAMP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup 1: Database
echo "Backing up database..."
if ! docker exec webapp_core_db_fresh mysqldump -uroot -proot --all-databases 2>/dev/null | \
     gzip > "$DB_BACKUP"; then
  echo "❌ Database backup failed"
  exit 1
fi
DB_SIZE=$(ls -lh "$DB_BACKUP" | awk '{print $5}')
echo "✓ Database backed up: $DB_BACKUP ($DB_SIZE)"

# Backup 2: Gateway config
echo "Backing up gateway config..."
CONFIG_BACKUP="$BACKUP_DIR/gateway_config_$TIMESTAMP.tar.gz"
tar -czf "$CONFIG_BACKUP" \
  -C "$(dirname $(pwd))/customer-service-gateway" \
  .env .env.example docker-compose.yml Dockerfile > /dev/null 2>&1 || true
CONFIG_SIZE=$(ls -lh "$CONFIG_BACKUP" 2>/dev/null | awk '{print $5}' || echo "0B")
echo "✓ Gateway config backed up: $CONFIG_BACKUP ($CONFIG_SIZE)"

# Backup 3: webapp_core config
echo "Backing up webapp_core config..."
WEBAPP_BACKUP="$BACKUP_DIR/webapp_config_$TIMESTAMP.tar.gz"
tar -czf "$WEBAPP_BACKUP" \
  -C "../webapp_core" \
  .env .env.example docker-compose.local.yml > /dev/null 2>&1 || true
WEBAPP_SIZE=$(ls -lh "$WEBAPP_BACKUP" 2>/dev/null | awk '{print $5}' || echo "0B")
echo "✓ Webapp config backed up: $WEBAPP_BACKUP ($WEBAPP_SIZE)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Backup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Recent backups:"
ls -lh "$BACKUP_DIR" | tail -6
echo ""
echo "To restore: bash scripts/restore.sh <backup_file>"
