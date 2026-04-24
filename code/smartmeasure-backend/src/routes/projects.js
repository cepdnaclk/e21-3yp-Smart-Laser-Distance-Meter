const express = require('express');
const pool = require('../db/db');
const authMiddleware = require('../middleware/auth_middleware');

const router = express.Router();

// Protect all routes
router.use(authMiddleware);

// GET /projects — list all projects for logged in user
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM projects WHERE user_id = $1 ORDER BY updated_at DESC',
      [req.user.userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// POST /projects — create new project
router.post('/', async (req, res) => {
  try {
    const { name, local_id } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'Project name is required' });
    }

    const result = await pool.query(
      `INSERT INTO projects (user_id, name, local_id)
       VALUES ($1, $2, $3) RETURNING *`,
      [req.user.userId, name, local_id]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// DELETE /projects/:id
router.delete('/:id', async (req, res) => {
  try {
    await pool.query(
      'DELETE FROM projects WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user.userId]
    );
    res.json({ message: 'Project deleted successfully' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;