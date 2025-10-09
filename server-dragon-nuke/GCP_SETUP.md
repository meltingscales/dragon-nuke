# GCP Setup Guide

## 1. Create a GCP Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your Project ID (should be: dragon-nuke)

## 2. Enable Required APIs

```bash
gcloud services enable storage-api.googleapis.com
```

## 3. Create a Storage Bucket

```bash
# Create bucket
gsutil mb gs://dragon-nuke-bucket

# Make bucket private (default)
gsutil iam ch -d allUsers:objectViewer gs://dragon-nuke-bucket

# For Android app to work with simple auth, you may need to make it publicly writable:
# gsutil iam ch allUsers:objectAdmin gs://dragon-nuke-bucket
# WARNING: This allows anyone to write to your bucket. Use with caution.
```

## 4. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create dragon-nuke-service \
    --description="Service account for DragonNuke system" \
    --display-name="DragonNuke Service"

# Create and download key
gcloud iam service-accounts keys create ~/dragon-nuke-key.json \
    --iam-account=dragon-nuke-service@dragon-nuke.iam.gserviceaccount.com

# Grant storage permissions
gcloud projects add-iam-policy-binding dragon-nuke \
    --member="serviceAccount:dragon-nuke-service@dragon-nuke.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"
```

## 5. Initialize the Trigger File

```bash
# Create initial "safe" state
echo "safe" | gsutil cp - gs://dragon-nuke-bucket/nuke-trigger.txt

# Verify it was created
gsutil cat gs://dragon-nuke-bucket/nuke-trigger.txt
```

## 6. Configure Environment

1. Copy `.env.example` to `.env`:
```bash
cp ../.env.example .env
```

2. Edit `.env` with your values:
```env
GOOGLE_CLOUD_PROJECT_ID=dragon-nuke
GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/dragon-nuke-key.json
GCP_BUCKET_NAME=dragon-nuke-bucket
GCP_FILE_NAME=nuke-trigger.txt
POLL_INTERVAL_SECONDS=10
LOG_FILE=/var/log/dragon-nuke.log
VERBOSE_LOGGING=false
```

## 7. Test Configuration

```bash
# Test server connection
just test-gcp

# Start server in debug mode
just debug

# Test trigger manually
just trigger-nuke
```

## 8. Android App Setup

For the Android app to work:

1. Copy the service account key (`dragon-nuke-key.json`) to your phone
2. Open the Dragon Nuke app
3. Load the service account key file
4. Tap "TRIGGER NUKE" to test

## Security Notes

- Keep your service account key secure
- Use IAM roles with minimal required permissions
- Consider using Workload Identity in production
- Monitor bucket access logs
- Set up billing alerts to prevent unexpected charges
- For production, implement proper OAuth instead of embedded service account keys