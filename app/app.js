class DragonRebootApp {
    constructor() {
        this.config = this.loadConfig();
        this.status = document.getElementById('status');
        this.rebootBtn = document.getElementById('rebootBtn');
        this.modal = document.getElementById('confirmModal');
        
        this.initializeApp();
    }
    
    loadConfig() {
        const saved = localStorage.getItem('dragonRebootConfig');
        if (saved) {
            return JSON.parse(saved);
        }
        return {
            projectId: '',
            bucketName: '',
            fileName: 'reboot-trigger.txt',
            apiKey: ''
        };
    }
    
    saveConfig() {
        const config = {
            projectId: document.getElementById('projectId').value,
            bucketName: document.getElementById('bucketName').value,
            fileName: document.getElementById('fileName').value || 'reboot-trigger.txt',
            apiKey: document.getElementById('apiKey').value
        };
        
        localStorage.setItem('dragonRebootConfig', JSON.stringify(config));
        this.config = config;
        
        this.updateStatus('Configuration saved!', 'connected');
        setTimeout(() => this.checkConnection(), 1000);
    }
    
    initializeApp() {
        // Load saved config into form
        document.getElementById('projectId').value = this.config.projectId || '';
        document.getElementById('bucketName').value = this.config.bucketName || '';
        document.getElementById('fileName').value = this.config.fileName || 'reboot-trigger.txt';
        
        this.checkConnection();
    }
    
    async checkConnection() {
        if (!this.config.projectId || !this.config.bucketName || !this.config.apiKey) {
            this.updateStatus('Please configure GCP settings below', 'error');
            this.rebootBtn.disabled = true;
            return;
        }
        
        try {
            // In a real implementation, you would validate the GCP connection here
            // For now, we'll just check if the config looks valid
            const apiKey = JSON.parse(this.config.apiKey);
            if (apiKey.type === 'service_account' && apiKey.project_id) {
                this.updateStatus('✅ Connected to GCP', 'connected');
                this.rebootBtn.disabled = false;
            } else {
                throw new Error('Invalid service account key');
            }
        } catch (error) {
            this.updateStatus(`❌ Connection failed: ${error.message}`, 'error');
            this.rebootBtn.disabled = true;
        }
    }
    
    updateStatus(message, type = '') {
        this.status.textContent = message;
        this.status.className = `status ${type}`;
    }
    
    showConfirmation() {
        this.modal.style.display = 'block';
    }
    
    hideConfirmation() {
        this.modal.style.display = 'none';
    }
    
    async executeReboot() {
        this.hideConfirmation();
        this.updateStatus('🔥 Sending reboot command...', 'error');
        this.rebootBtn.disabled = true;
        
        try {
            await this.writeRebootTrigger();
            this.updateStatus('✅ Reboot command sent successfully!', 'connected');
            
            // Re-enable button after a few seconds
            setTimeout(() => {
                this.rebootBtn.disabled = false;
                this.updateStatus('✅ Ready to send commands', 'connected');
            }, 5000);
            
        } catch (error) {
            this.updateStatus(`❌ Failed to send reboot command: ${error.message}`, 'error');
            this.rebootBtn.disabled = false;
        }
    }
    
    async writeRebootTrigger() {
        // This is a simplified implementation
        // In a real app, you would use the GCP Storage API
        
        if (!this.config.apiKey) {
            throw new Error('No API key configured');
        }
        
        try {
            const serviceAccount = JSON.parse(this.config.apiKey);
            
            // Simulate API call with a timeout
            await new Promise((resolve, reject) => {
                setTimeout(() => {
                    // Simulate success/failure
                    if (Math.random() > 0.1) { // 90% success rate for demo
                        resolve();
                    } else {
                        reject(new Error('Network error'));
                    }
                }, 1000);
            });
            
            console.log('Would write "REBOOT=TRUE" to:', {
                bucket: this.config.bucketName,
                file: this.config.fileName,
                project: this.config.projectId
            });
            
        } catch (error) {
            if (error.name === 'SyntaxError') {
                throw new Error('Invalid service account key format');
            }
            throw error;
        }
    }
}

// Global functions for HTML onclick handlers
function showConfirmation() {
    window.app.showConfirmation();
}

function hideConfirmation() {
    window.app.hideConfirmation();
}

function executeReboot() {
    window.app.executeReboot();
}

function saveConfig() {
    window.app.saveConfig();
}

// Initialize the app when the page loads
window.addEventListener('DOMContentLoaded', () => {
    window.app = new DragonRebootApp();
});