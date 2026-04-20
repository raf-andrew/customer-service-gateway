#!/bin/bash
# restore.sh - Restore database from backup
# Usage: bash scripts/restore.sh <backup_file.sql.gz>
# Example: bash scripts/restore.sh ../webapp_core/backups/webapp_core_20260420_031500.sql.gz

set -e

if [ -z "$1" ]; then
  echo "Usage: bash scripts/restore.sh <backup_file>"
  echo ""
  echo "Available backups:"
  ls -lh ../webapp_core/backups/*.sql.gz 2>/dev/null | tail -5 || echo "No backups found"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Database Restore"
echo "  File: $(basename $BACKUP_FILE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Confirm
echo "⚠️  WARNING: This will overwrite the current database!"
echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
sleep 5

echo ""
echo "Step 1: Checking database connectivity..."
if ! docker exec webapp_core_db_fresh mysql -uroot -proot -e "SELECT 1;" > /dev/null 2>&1; then
  echo "❌ Database not accessible"
  exit 1
fi
echo "✓ Database accessible"

echo ""
echo "Step 2: Restoring database..."
if gunzip -c "$BACKUP_FILE" | \
   docker exec -i webapp_core_db_fresh mysql -uroot -proot 2>/dev/null; then
  echo "✓ Database restored"
else
  echo "❌ Restore failed"
  exit 1
fi

echo ""
echo "Step 3: Verifying restore..."
TABLE_COUNT=$(docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='webapp_core';" \
  2>/dev/null | tail -1)
echo "✓ Tables found: $TABLE_COUNT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Restore Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Run health-check.sh to verify everything is working"
