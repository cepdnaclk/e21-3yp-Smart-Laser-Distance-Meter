const express = require('express');
const authMiddleware = require('../middleware/auth_middleware');

const router = express.Router();

// Temporary in-memory storage — will replace with PostgreSQL later
const projects = [];

// Apply authMiddleware to ALL routes in this file
// This means every request here must have a valid JWT token
router.use(authMiddleware);

// GET /projects — list all projects for the logged-in user
router.get('/', (req, res) => {
  // req.user.userId was set by authMiddleware
  const userProjects = projects.filter(p => p.userId === req.user.userId);
  res.json(userProjects);
});

// POST /projects — create a new project
router.post('/', (req, res) => {
  const { name } = req.body;

  if (!name) {
    return res.status(400).json({ error: 'Project name is required' });
  }

  const newProject = {
    id: projects.length + 1,
    userId: req.user.userId,
    name: name,
    created_at: new Date().toISOString(),
  };

  projects.push(newProject);
  res.status(201).json(newProject);
});

// DELETE /projects/:id — delete a project
router.delete('/:id', (req, res) => {
  const projectId = parseInt(req.params.id);
  const index = projects.findIndex(
    p => p.id === projectId && p.userId === req.user.userId
  );

  if (index === -1) {
    return res.status(404).json({ error: 'Project not found' });
  }

  projects.splice(index, 1);
  res.json({ message: 'Project deleted successfully' });
});

module.exports = router;