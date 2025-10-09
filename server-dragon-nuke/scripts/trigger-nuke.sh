#!/usr/bin/env bash

echo "⚠️  WARNING: This will trigger an actual filesystem nuke on all listeners!"
echo "Type 'YES' to confirm:"
read -r confirm

if [ "$confirm" = "YES" ]; then
    echo "✅ Triggering nuke..."
    echo "NUKE=TRUE" | gsutil cp - gs://dragon-nuke-bucket/nuke-trigger.txt
    echo "✅ Nuke trigger sent to GCP bucket"
else
    echo "❌ Nuke cancelled"
    exit 1
fi