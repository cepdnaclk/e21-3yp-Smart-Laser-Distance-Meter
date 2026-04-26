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

    const inviteCode = Math.random().toString(36).substring(2, 6).toUpperCase() +
                       Math.random().toString(36).substring(2, 6).toUpperCase();

    const result = await pool.query(
      `INSERT INTO projects (user_id, name, local_id, invite_code)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [req.user.userId, name, local_id, inviteCode]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /projects/shared
router.get('/shared', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT p.*, pc.role, u.email AS owner_email
       FROM project_collaborators pc
       JOIN projects p ON p.id = pc.project_id
       JOIN users u ON u.id = p.user_id
       WHERE pc.user_id = $1 AND pc.status = 'accepted'
       ORDER BY p.updated_at DESC`,
      [req.user.userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// POST /projects/join
router.post('/join', async (req, res) => {
  try {
    const { invite_code } = req.body;
    if (!invite_code) return res.status(400).json({ error: 'Invite code required' });

    const projectResult = await pool.query(
      `SELECT p.*, u.email AS owner_email
       FROM projects p JOIN users u ON u.id = p.user_id
       WHERE p.invite_code = $1`,
      [invite_code.toUpperCase().trim()]
    );
    if (projectResult.rows.length === 0) {
      return res.status(404).json({ error: 'Invalid invite code' });
    }
    const project = projectResult.rows[0];
    if (project.user_id === req.user.userId) {
      return res.status(400).json({ error: 'You already own this project' });
    }
    const existing = await pool.query(
      'SELECT id, status FROM project_collaborators WHERE project_id = $1 AND user_id = $2',
      [project.id, req.user.userId]
    );
    if (existing.rows.length > 0 && existing.rows[0].status === 'accepted') {
      return res.status(409).json({ error: 'Already a collaborator' });
    }
    if (existing.rows.length > 0) {
      await pool.query(
        `UPDATE project_collaborators SET status = 'accepted', joined_at = NOW()
         WHERE project_id = $1 AND user_id = $2`,
        [project.id, req.user.userId]
      );
    } else {
      await pool.query(
        `INSERT INTO project_collaborators (project_id, user_id, role, status)
         VALUES ($1, $2, 'editor', 'accepted')`,
        [project.id, req.user.userId]
      );
    }
    res.json({
      message: 'Joined successfully',
      project: {
        id: project.id,
        name: project.name,
        owner_email: project.owner_email,
        updated_at: project.updated_at,
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /projects/:id/invite-code
router.get('/:id/invite-code', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT invite_code FROM projects WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ invite_code: result.rows[0].invite_code });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /projects/:id/collaborators
router.get('/:id/collaborators', async (req, res) => {
  try {
    const ownerCheck = await pool.query(
      'SELECT id FROM projects WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user.userId]
    );
    if (ownerCheck.rows.length === 0) return res.status(403).json({ error: 'Access denied' });
    const result = await pool.query(
      `SELECT u.email, pc.role, pc.status, pc.joined_at
       FROM project_collaborators pc JOIN users u ON u.id = pc.user_id
       WHERE pc.project_id = $1 ORDER BY pc.joined_at ASC`,
      [req.params.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// DELETE /projects/:id/leave
router.delete('/:id/leave', async (req, res) => {
  try {
    await pool.query(
      'DELETE FROM project_collaborators WHERE project_id = $1 AND user_id = $2',
      [req.params.id, req.user.userId]
    );
    res.json({ message: 'Left project' });
  } catch (err) {
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