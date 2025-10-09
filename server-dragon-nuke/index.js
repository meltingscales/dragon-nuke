#!/usr/bin/env node

const { Storage } = require("@google-cloud/storage");
const { exec } = require("child_process");
const path = require("path");
const fs = require("fs").promises;
require("dotenv").config();

class DragonNukeServer {
  constructor() {
    this.storage = new Storage({
      projectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
      keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    });

    this.bucketName = process.env.GCP_BUCKET_NAME;
    this.fileName = process.env.GCP_FILE_NAME || "nuke-trigger.txt";
    this.pollInterval = (process.env.POLL_INTERVAL_SECONDS || 10) * 1000;
    this.bucket = this.storage.bucket(this.bucketName);
    this.file = this.bucket.file(this.fileName);

    this.isRunning = false;
    this.lastContent = null;
    this.logFile = process.env.LOG_FILE || "/var/log/dragon-nuke.log";
    this.verboseLogging = process.env.VERBOSE_LOGGING === "true";
    this.pollCount = 0;
    this.lastSuccessfulPoll = null;
    this.errorCount = 0;
  }

  async logMessage(message, level = "INFO") {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] [${level}] ${message}\n`;

    // Console output
    console.log(`[${timestamp}] ${message}`);

    // File logging
    try {
      await fs.appendFile(this.logFile, logEntry);
    } catch (error) {
      console.error("Failed to write to log file:", error.message);
    }
  }

  async checkFileContent() {
    const startTime = Date.now();
    this.pollCount++;

    try {
      if (this.verboseLogging) {
        await this.logMessage(
          `Poll #${this.pollCount}: Checking GCP file existence...`,
          "DEBUG",
        );
      }

      const [exists] = await this.file.exists();
      if (!exists) {
        await this.logMessage(
          `File ${this.fileName} does not exist in bucket ${this.bucketName}`,
          "WARN",
        );
        this.errorCount++;
        return null;
      }

      if (this.verboseLogging) {
        await this.logMessage("File exists, downloading content...", "DEBUG");
      }

      const [content] = await this.file.download();
      const contentString = content.toString().trim();
      const downloadTime = Date.now() - startTime;

      // Log file access details
      const [metadata] = await this.file.getMetadata();
      await this.logMessage(
        `Poll #${this.pollCount}: Content="${contentString}" (${content.length} bytes, ${downloadTime}ms)`,
        "INFO",
      );

      if (this.verboseLogging) {
        await this.logMessage(
          `File metadata: Updated=${metadata.updated}, Size=${metadata.size}, ETag=${metadata.etag}`,
          "DEBUG",
        );
      }

      this.lastSuccessfulPoll = new Date();
      this.errorCount = 0; // Reset error count on success

      return contentString;
    } catch (error) {
      this.errorCount++;
      await this.logMessage(
        `Error reading file from GCP (attempt ${this.errorCount}): ${error.message}`,
        "ERROR",
      );

      if (this.verboseLogging) {
        await this.logMessage(`Full error details: ${error.stack}`, "DEBUG");
      }

      return null;
    }
  }

  async getHealthStatus() {
    const uptime = process.uptime();
    const memUsage = process.memoryUsage();

    return {
      status: this.isRunning ? "running" : "stopped",
      uptime: `${Math.floor(uptime / 3600)}h ${Math.floor((uptime % 3600) / 60)}m ${Math.floor(uptime % 60)}s`,
      pollCount: this.pollCount,
      lastSuccessfulPoll: this.lastSuccessfulPoll,
      errorCount: this.errorCount,
      nextPollIn: this.isRunning
        ? `${Math.ceil(this.pollInterval / 1000)}s`
        : "N/A",
      memory: {
        rss: `${Math.round(memUsage.rss / 1024 / 1024)}MB`,
        heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
        external: `${Math.round(memUsage.external / 1024 / 1024)}MB`,
      },
      config: {
        bucket: this.bucketName,
        file: this.fileName,
        pollInterval: `${this.pollInterval / 1000}s`,
        verboseLogging: this.verboseLogging,
      },
    };
  }

  async executeNuke() {
    await this.logMessage(
      "🔥 NUKE TRIGGER DETECTED! Starting nuke sequence...",
      "WARN",
    );

    // Execute the nuke script
    const scriptPath = path.join(__dirname, "scripts", "dragon-nuke.sh");
    await this.logMessage(`Executing nuke script: ${scriptPath}`, "INFO");

    exec(`sudo bash "${scriptPath}"`, async (error, stdout, stderr) => {
      if (error) {
        await this.logMessage(
          `Error executing nuke script: ${error.message}`,
          "ERROR",
        );
        return;
      }

      if (stdout) {
        await this.logMessage(`Nuke script output: ${stdout}`, "INFO");
      }

      if (stderr) {
        await this.logMessage(`Nuke script stderr: ${stderr}`, "WARN");
      }
    });
  }

  async poll() {
    if (!this.isRunning) return;

    const content = await this.checkFileContent();

    if (content === "NUKE=TRUE") {
      await this.executeNuke();
    }

    // Schedule next poll
    setTimeout(() => this.poll(), this.pollInterval);
  }

  async start() {
    // Check if running as root
    if (process.getuid && process.getuid() !== 0) {
      console.error(
        "❌ ERROR: DragonNukeServer must be run as root (use sudo)",
      );
      console.error("   This is required to execute required commands.");
      process.exit(1);
    }

    await this.logMessage("🐉 DragonNukeServer starting...", "INFO");
    await this.logMessage(
      `Running as UID: ${process.getuid ? process.getuid() : "unknown"}`,
      "INFO",
    );
    await this.logMessage(`Monitoring bucket: ${this.bucketName}`, "INFO");
    await this.logMessage(`Monitoring file: ${this.fileName}`, "INFO");
    await this.logMessage(
      `Poll interval: ${this.pollInterval / 1000} seconds`,
      "INFO",
    );
    await this.logMessage(`Verbose logging: ${this.verboseLogging}`, "INFO");
    await this.logMessage(`Log file: ${this.logFile}`, "INFO");

    // Verify GCP connection
    try {
      await this.checkFileContent();
      await this.logMessage("✅ GCP connection verified", "INFO");
    } catch (error) {
      await this.logMessage(
        `❌ Failed to connect to GCP: ${error.message}`,
        "ERROR",
      );
      process.exit(1);
    }

    this.isRunning = true;
    this.poll();

    await this.logMessage("🔍 Monitoring for nuke triggers...", "INFO");

    // Log health status every 5 minutes
    setInterval(
      async () => {
        if (this.verboseLogging) {
          const health = await this.getHealthStatus();
          await this.logMessage(
            `Health check: ${JSON.stringify(health, null, 2)}`,
            "DEBUG",
          );
        }
      },
      5 * 60 * 1000,
    );
  }

  stop() {
    console.log("🛑 DragonNukeServer stopping...");
    this.isRunning = false;
  }
}

// Handle graceful shutdown
process.on("SIGINT", () => {
  console.log("\n📭 Received SIGINT, shutting down gracefully...");
  if (server) {
    server.stop();
  }
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\n📭 Received SIGTERM, shutting down gracefully...");
  if (server) {
    server.stop();
  }
  process.exit(0);
});

// Start the server
const server = new DragonNukeServer();
server.start().catch((error) => {
  console.error("Failed to start DragonNukeServer:", error);
  process.exit(1);
});
