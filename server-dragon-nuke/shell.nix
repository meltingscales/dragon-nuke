{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Node.js (includes npm)
    nodejs
    
    # GCP CLI tools
    google-cloud-sdk
    
    # Development tools
    just
    
    # System utilities
    curl
    wget
    
    # Text processing (for monitoring scripts)
    gnugrep
    gnused
    coreutils
  ];

  shellHook = ''
    echo "🐉 DragonNuke Server Development Environment"
    echo ""
    echo "Available tools:"
    echo "  - Node.js $(node --version)"
    echo "  - npm $(npm --version)"
    echo "  - gcloud $(gcloud --version | head -1)"
    echo "  - gsutil (part of gcloud)"
    echo "  - just $(just --version 2>/dev/null || echo 'available')"
    echo ""
    echo "GCP Configuration:"
    echo "  Project: dragon-nuke"
    echo "  Bucket: gs://dragon-nuke-bucket"
    echo ""
    echo "Quick commands:"
    echo "  just setup      # Initial setup"
    echo "  just start-root # Start server (as root)"
    echo "  just debug      # Debug mode"
    echo "  just test-gcp   # Test GCP connection"
    echo ""
    
    # Set up GCP project if not already configured
    if ! gcloud config get-value project >/dev/null 2>&1; then
      echo "Setting up GCP project..."
      gcloud config set project dragon-nuke
    fi
    
    # Ensure .env exists
    if [ ! -f .env ]; then
      echo "Creating .env file from example..."
      if [ -f ../.env.example ]; then
        cp ../.env.example .env
        echo "⚠️  Please edit .env with your service account key path"
      else
        echo "⚠️  .env.example not found in parent directory"
      fi
    fi
  '';

  # Environment variables for the shell
  GOOGLE_CLOUD_PROJECT = "dragon-nuke";
  GCP_BUCKET_NAME = "dragon-nuke-bucket";
}