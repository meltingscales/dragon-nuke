#!/usr/bin/env bash

echo "⚠️  WARNING: This will trigger an actual reboot!"
echo "Type 'YES' to confirm:"
read -r confirm

if [ "$confirm" = "YES" ]; then
    echo "✅ Triggering reboot..."
    echo "REBOOT=TRUE" | gsutil cp - gs://dragon-reboot-bucket/reboot-trigger.txt
    echo "✅ Reboot trigger sent to GCP bucket"
else
    echo "❌ Reboot cancelled"
    exit 1
fi