# GCP Setup Guide

## 1. Create a GCP Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your Project ID

## 2. Enable Required APIs

```bash
gcloud services enable storage-api.googleapis.com
```

## 3. Create a Storage Bucket

```bash
# Create bucket (replace YOUR_BUCKET_NAME with your desired name)
gsutil mb gs://dragon-reboot-bucket

# Make bucket private
gsutil iam ch -d allUsers:objectViewer gs://dragon-reboot-bucket
```

## 4. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create dragon-reboot-service \
    --description="Service account for DragonReboot system" \
    --display-name="DragonReboot Service"

# Create and download key
gcloud iam service-accounts keys create ~/dragon-reboot-key.json \
    --iam-account=dragon-reboot-service@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Grant storage permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:dragon-reboot-service@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"
```

## 5. Initialize the Trigger File

```bash
# Create initial "safe" state
echo "safe" | gsutil cp - gs://dragon-reboot-bucket/reboot-trigger.txt
```

## 6. Configure Environment

1. Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

2. Edit `.env` with your values:
```env
GOOGLE_CLOUD_PROJECT_ID=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/dragon-reboot-key.json
GCP_BUCKET_NAME=dragon-reboot-bucket
GCP_FILE_NAME=reboot-trigger.txt
POLL_INTERVAL_SECONDS=10
```

## 7. Test Configuration

```bash
# Test server connection
npm start

# Test app interface
npm run app
```

## Security Notes

- Keep your service account key secure
- Use IAM roles with minimal required permissions
- Consider using Workload Identity in production
- Monitor bucket access logs
- Set up billing alerts to prevent unexpected charges