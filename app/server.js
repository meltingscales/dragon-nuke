const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Serve static files from the app directory
app.use(express.static(__dirname));

// Serve the main app
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, () => {
    console.log(`🐉 DragonReboot App running on http://localhost:${PORT}`);
    console.log('Access this URL from your phone to control the reboot system');
});