const express = require('express');
const pool = require('../db/db');
const authMiddleware = require('../middleware/auth_middleware');

const router = express.Router();

// Protect all routes
router.use(authMiddleware);

// POST /sync/upload
// Flutter sends the entire project data here to save to cloud
router.post('/upload', async (req, res) => {
  const client = await pool.connect();
  try {
    const { project, shapes, roomObjects } = req.body;

    // transaction — either everything saves or nothing saves
    await client.query('BEGIN');

    // 1. Upsert project
    let cloudProjectId;
    const existing = await client.query(
      'SELECT id FROM projects WHERE user_id = $1 AND local_id = $2',
      [req.user.userId, project.local_id]
    );
    if (existing.rows.length > 0) {
      cloudProjectId = existing.rows[0].id;
      await client.query(
        'UPDATE projects SET name = $1, updated_at = NOW() WHERE id = $2',
        [project.name, cloudProjectId]
      );
      const oldShapes = await client.query(
        'SELECT id FROM shapes WHERE project_id = $1', [cloudProjectId]
      );
      for (const row of oldShapes.rows) {
        await client.query('DELETE FROM shape_points  WHERE shape_id = $1', [row.id]);
        await client.query('DELETE FROM wall_real_mm  WHERE shape_id = $1', [row.id]);
        await client.query('DELETE FROM wall_angles   WHERE shape_id = $1', [row.id]);
        await client.query('DELETE FROM wall_lengths  WHERE shape_id = $1', [row.id]);
      }
      await client.query('DELETE FROM shapes       WHERE project_id = $1', [cloudProjectId]);
      await client.query('DELETE FROM room_objects  WHERE project_id = $1', [cloudProjectId]);
    } else {
      const projectResult = await client.query(
        `INSERT INTO projects (user_id, name, local_id, updated_at)
         VALUES ($1, $2, $3, NOW()) RETURNING id`,
        [req.user.userId, project.name, project.local_id]
      );
      cloudProjectId = projectResult.rows[0].id;
    }

    // 2. Save each shape
    for (const shape of shapes) {
      const shapeResult = await client.query(
        `INSERT INTO shapes (project_id, shape_index, is_closed)
         VALUES ($1, $2, $3) RETURNING id`,
        [cloudProjectId, shape.shape_index, shape.is_closed]
      );
      const cloudShapeId = shapeResult.rows[0].id;

      // Save points
      for (const pt of shape.points) {
        await client.query(
          `INSERT INTO shape_points (shape_id, order_index, x, y)
           VALUES ($1, $2, $3, $4)`,
          [cloudShapeId, pt.order_index, pt.x, pt.y]
        );
      }

      // Save wall real mm
      for (const wm of shape.wall_real_mm) {
        await client.query(
          `INSERT INTO wall_real_mm (shape_id, wall_index, real_mm)
           VALUES ($1, $2, $3)`,
          [cloudShapeId, wm.wall_index, wm.real_mm]
        );
      }

      // Save wall angles
      for (const wa of shape.wall_angles) {
        await client.query(
          `INSERT INTO wall_angles (shape_id, order_index, angle)
           VALUES ($1, $2, $3)`,
          [cloudShapeId, wa.order_index, wa.angle]
        );
      }

      // Save wall lengths
      for (const wl of shape.wall_lengths) {
        await client.query(
          `INSERT INTO wall_lengths (shape_id, order_index, length)
           VALUES ($1, $2, $3)`,
          [cloudShapeId, wl.order_index, wl.length]
        );
      }
    }

    // 3. Save room objects (doors and windows)
    for (const obj of roomObjects) {
      await client.query(
        `INSERT INTO room_objects
         (project_id, object_id, type, wall_index, position_along,
          width_mm, height_mm, elevation_mm)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          cloudProjectId,
          obj.object_id,
          obj.type,
          obj.wall_index,
          obj.position_along,
          obj.width_mm,
          obj.height_mm,
          obj.elevation_mm,
        ]
      );
    }

    await client.query('COMMIT'); // save everything

    res.json({
      message: 'Project uploaded successfully',
      cloud_project_id: cloudProjectId,
    });

  } catch (err) {
    await client.query('ROLLBACK'); // undo everything if error
    console.error(err);
    res.status(500).json({ error: 'Upload failed' });
  } finally {
    client.release();
  }
});

// GET /sync/download/:projectId
// Flutter calls this to get a full project from cloud
router.get('/download/:projectId', async (req, res) => {
  try {
    const projectId = req.params.projectId;

    // Verify access: owner or accepted collaborator
    const projectResult = await pool.query(
      `SELECT p.* FROM projects p
       WHERE p.id = $1
         AND (
           p.user_id = $2
           OR EXISTS (
             SELECT 1 FROM project_collaborators pc
             WHERE pc.project_id = p.id
               AND pc.user_id = $2
               AND pc.status = 'accepted'
           )
         )`,
      [projectId, req.user.userId]
    );

    if (projectResult.rows.length === 0) {
      return res.status(404).json({ error: 'Project not found or access denied' });
    }

    // Get all shapes for this project
    const shapesResult = await pool.query(
      'SELECT * FROM shapes WHERE project_id = $1 ORDER BY shape_index ASC',
      [projectId]
    );

    // For each shape get its points, wall data
    const shapesWithData = await Promise.all(
      shapesResult.rows.map(async (shape) => {
        const points = await pool.query(
          'SELECT * FROM shape_points WHERE shape_id = $1 ORDER BY order_index ASC',
          [shape.id]
        );
        const wallMm = await pool.query(
          'SELECT * FROM wall_real_mm WHERE shape_id = $1',
          [shape.id]
        );
        const wallAngles = await pool.query(
          'SELECT * FROM wall_angles WHERE shape_id = $1 ORDER BY order_index ASC',
          [shape.id]
        );
        const wallLengths = await pool.query(
          'SELECT * FROM wall_lengths WHERE shape_id = $1 ORDER BY order_index ASC',
          [shape.id]
        );

        return {
          ...shape,
          points: points.rows,
          wall_real_mm: wallMm.rows,
          wall_angles: wallAngles.rows,
          wall_lengths: wallLengths.rows,
        };
      })
    );

    // Get room objects for this project
    const objectsResult = await pool.query(
      'SELECT * FROM room_objects WHERE project_id = $1',
      [projectId]
    );

    res.json({
      project: projectResult.rows[0],
      shapes: shapesWithData,
      roomObjects: objectsResult.rows,
    });

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Download failed' });
  }
});

// GET /sync/updates/:projectId?since=<ISO_timestamp>
router.get('/updates/:projectId', async (req, res) => {
  try {
    const projectId = req.params.projectId;
    const since = req.query.since;

    const accessCheck = await pool.query(
      `SELECT p.* FROM projects p
       WHERE p.id = $1
         AND (
           p.user_id = $2
           OR EXISTS (
             SELECT 1 FROM project_collaborators pc
             WHERE pc.project_id = p.id
               AND pc.user_id = $2
               AND pc.status = 'accepted'
           )
         )`,
      [projectId, req.user.userId]
    );
    if (accessCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Access denied' });
    }

    const project = accessCheck.rows[0];
    if (since && project.updated_at) {
      const serverTime = new Date(project.updated_at).getTime();
      const clientTime = new Date(since).getTime();
      if (serverTime <= clientTime) {
        return res.json({ updated: false });
      }
    }

    const shapesResult = await pool.query(
      'SELECT * FROM shapes WHERE project_id = $1 ORDER BY shape_index ASC',
      [projectId]
    );
    const shapesWithData = await Promise.all(
      shapesResult.rows.map(async (shape) => {
        const [points, wallMm, wallAngles, wallLengths] = await Promise.all([
          pool.query('SELECT * FROM shape_points WHERE shape_id = $1 ORDER BY order_index ASC', [shape.id]),
          pool.query('SELECT * FROM wall_real_mm  WHERE shape_id = $1', [shape.id]),
          pool.query('SELECT * FROM wall_angles   WHERE shape_id = $1 ORDER BY order_index ASC', [shape.id]),
          pool.query('SELECT * FROM wall_lengths  WHERE shape_id = $1 ORDER BY order_index ASC', [shape.id]),
        ]);
        return { ...shape, points: points.rows, wall_real_mm: wallMm.rows,
                 wall_angles: wallAngles.rows, wall_lengths: wallLengths.rows };
      })
    );
    const objectsResult = await pool.query(
      'SELECT * FROM room_objects WHERE project_id = $1', [projectId]
    );

    res.json({
      updated: true,
      project,
      shapes: shapesWithData,
      roomObjects: objectsResult.rows,
    });

  } catch (err) {
    console.error('Updates error:', err);
    res.status(500).json({ error: 'Failed to check updates' });
  }
});

module.exports = router;