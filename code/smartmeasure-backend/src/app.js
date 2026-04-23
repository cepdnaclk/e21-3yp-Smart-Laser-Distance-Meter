const express = require('express');
const cors = require('cors');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const projectRoutes = require('./routes/projects');

const app = express();

// These run on every single request before it reaches your routes
app.use(cors());           // allows Flutter app to talk to this server
app.use(express.json());   // automatically reads JSON from request body

// Routes — the URL prefix decides which file handles the request
app.use('/auth', authRoutes);
app.use('/projects', projectRoutes);

// Health check — visit this to confirm server is running
app.get('/health', (req, res) => {
  res.json({ status: 'OK', message: 'SmartMeasure backend running' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});