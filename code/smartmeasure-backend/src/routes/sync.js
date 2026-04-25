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

    // 1. Save project row
    const projectResult = await client.query(
      `INSERT INTO projects (user_id, name, local_id, updated_at)
       VALUES ($1, $2, $3, NOW()) RETURNING id`,
      [req.user.userId, project.name, project.local_id]
    );
    const cloudProjectId = projectResult.rows[0].id;

    // 2. Save each shape
    for (const shape of shapes) {
      const shapeResult = await client.query(
        `INSERT INTO shapes (project_id, shape_index, is_closed)
         VALUES ($1, $2, $3) RETURNING id`,
        [cloudProjectId, shape.shape_index, shape.is_closed ? 1 : 0]
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

    // Verify this project belongs to the logged in user
    const projectResult = await pool.query(
      'SELECT * FROM projects WHERE id = $1 AND user_id = $2',
      [projectId, req.user.userId]
    );

    if (projectResult.rows.length === 0) {
      return res.status(404).json({ error: 'Project not found' });
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

module.exports = router;