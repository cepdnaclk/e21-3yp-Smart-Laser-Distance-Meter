// tests/sync.upload.test.js
// Unit tests for POST /sync/upload
// Assigned to: Padukka V. K. (E/21/277)
//
// Mocks: PostgreSQL pool.connect()/client (src/db/db.js) and the JWT auth
// middleware. The transaction touches many tables, so the mock client.query
// routes its response based on which SQL statement was run, rather than
// relying on call order (the code branches a lot depending on input).

const request = require('supertest');
const express = require('express');

jest.mock('../src/db/db', () => ({ connect: jest.fn(), query: jest.fn() }));
jest.mock('../src/middleware/auth_middleware', () => (req, res, next) => {
  req.user = { userId: 1 };
  next();
});

const pool = require('../src/db/db');
const syncRoutes = require('../src/routes/sync');

const app = express();
app.use(express.json());
app.use('/sync', syncRoutes);

/**
 * Builds a mock transaction client whose .query() responds based on the SQL
 * text of each call, matching the real branching logic in uploadProject().
 *
 * @param {object} opts
 * @param {object|null} opts.existingProject - { id, updated_at } or null for new project
 * @param {number} opts.ownerId - user_id stored on the existing project (for edit-access check)
 * @param {boolean} opts.canEdit - collaborator's can_edit flag, if not the owner
 * @param {string} opts.failOn - SQL prefix that should throw (simulates a DB failure)
 */
function makeClient(opts = {}) {
  const { existingProject = null, ownerId = 1, canEdit = true, failOn = null } = opts;
  let shapeIdCounter = 500;

  const query = jest.fn(async (sql) => {
    if (failOn && sql.startsWith(failOn)) {
      throw new Error(`${failOn} failed`);
    }
    if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') return {};
    if (sql.includes('SELECT id, updated_at FROM projects WHERE id = $1')) {
      return existingProject ? { rows: [existingProject] } : { rows: [] };
    }
    if (sql.includes('SELECT id, updated_at FROM projects WHERE user_id')) {
      return existingProject ? { rows: [existingProject] } : { rows: [] };
    }
    if (sql.includes('SELECT user_id FROM projects WHERE id = $1')) {
      return { rows: [{ user_id: ownerId }] };
    }
    if (sql.includes('SELECT can_edit FROM project_collaborators')) {
      return { rows: [{ can_edit: canEdit }] };
    }
    if (sql.startsWith('UPDATE projects SET name')) return {};
    if (sql.includes('SELECT id FROM shapes WHERE project_id')) return { rows: [] };
    if (sql.startsWith('DELETE FROM')) return {};
    if (sql.startsWith('INSERT INTO projects')) return { rows: [{ id: 100 }] };
    if (sql.startsWith('INSERT INTO shapes')) return { rows: [{ id: shapeIdCounter++ }] };
    if (sql.startsWith('INSERT INTO shape_points')) return {};
    if (sql.startsWith('INSERT INTO wall_real_mm')) return {};
    if (sql.startsWith('INSERT INTO wall_angles')) return {};
    if (sql.startsWith('INSERT INTO wall_lengths')) return {};
    if (sql.startsWith('INSERT INTO room_objects')) return {};
    if (sql.startsWith('INSERT INTO furniture_items')) return {};
    if (sql.includes('SELECT updated_at FROM projects WHERE id = $1')) {
      return { rows: [{ updated_at: new Date('2026-07-10T00:00:00Z') }] };
    }
    return { rows: [] };
  });

  return { query, release: jest.fn() };
}

function makeShape({ points = 3, withWallData = true } = {}) {
  return {
    shape_index: 0,
    is_closed: true,
    points: Array.from({ length: points }, (_, i) => ({ order_index: i, x: i, y: i })),
    wall_real_mm: withWallData ? [{ wall_index: 0, real_mm: 1000 }] : [],
    wall_angles: withWallData ? [{ order_index: 0, angle: 90 }] : [],
    wall_lengths: withWallData ? [{ order_index: 0, length: 1000 }] : [],
  };
}

describe('POST /sync/upload', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ---------- Equivalence classes ----------

  test('valid new project -> 200 OK, cloud_project_id returned', async () => {
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-1', name: 'Room A' },
        shapes: [makeShape()],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
    expect(res.body.cloud_project_id).toBe(100);
  });

  test('valid existing project, same local_id -> 200 OK, project updated', async () => {
    pool.connect.mockResolvedValueOnce(
      makeClient({ existingProject: { id: 55, updated_at: null }, ownerId: 1 })
    );

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-1', name: 'Room A' },
        shapes: [makeShape()],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
    expect(res.body.cloud_project_id).toBe(55);
  });

  test('empty shapes array -> 200 OK, project saved with no shapes', async () => {
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-2', name: 'Empty Room' },
        shapes: [],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
  });

  // ---------- Boundary value analysis (shape count) ----------

  test('project with 1 shape -> 200 OK', async () => {
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-3', name: 'One Shape' },
        shapes: [makeShape()],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
  });

  test('project with 50 shapes -> 200 OK', async () => {
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-4', name: 'Many Shapes' },
        shapes: Array.from({ length: 50 }, () => makeShape()),
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
  });

  test('shape with exactly 3 points (minimum for a polygon) -> 200 OK', async () => {
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-5', name: 'Triangle' },
        shapes: [makeShape({ points: 3 })],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
  });

  test('[GAP] shape with only 2 points is currently saved without rejection -> actual: 200', async () => {
    // The table notes "saved but invalid polygon" — the code has no check
    // requiring at least 3 points, so this silently succeeds. Worth raising
    // in the Step 3 review: should the route validate points.length >= 3?
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-6', name: 'Invalid Polygon' },
        shapes: [makeShape({ points: 2 })],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
  });

  // ---------- Error / negative cases ----------

  test('database failure mid-transaction -> ROLLBACK, 500 error', async () => {
    const client = makeClient({ existingProject: null, failOn: 'INSERT INTO shapes' });
    pool.connect.mockResolvedValueOnce(client);

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-7', name: 'Will Fail' },
        shapes: [makeShape()],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(500);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
  });

  test('database COMMIT fails -> ROLLBACK, 500 error', async () => {
    const client = makeClient({ existingProject: null, failOn: 'COMMIT' });
    pool.connect.mockResolvedValueOnce(client);

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-8', name: 'Commit Fails' },
        shapes: [makeShape()],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(500);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
  });

  // ---------- Known gaps ----------

  test('[GAP] missing project name -> actual: 200 (no name validation exists)', async () => {
    // Table expects 400 Bad Request, but uploadProject() never checks
    // project.name before using it — it's inserted/updated as-is (even null).
    pool.connect.mockResolvedValueOnce(makeClient({ existingProject: null }));

    const res = await request(app)
      .post('/sync/upload')
      .send({
        project: { local_id: 'local-9' }, // name omitted
        shapes: [makeShape()],
        roomObjects: [],
        furnitureItems: [],
      });

    expect(res.status).toBe(200);
  });

  test('[GAP] null project body -> actual: 500 (crashes reading project.cloud_project_id)', async () => {
    // Table expects 400 Bad Request, but the code has no upfront check for a
    // missing "project" key — it immediately does project.cloud_project_id,
    // which throws a TypeError on undefined, caught by the outer try/catch as 500.
    const client = makeClient({ existingProject: null });
    pool.connect.mockResolvedValueOnce(client);

    const res = await request(app)
      .post('/sync/upload')
      .send({ shapes: [], roomObjects: [], furnitureItems: [] }); // no "project" key

    expect(res.status).toBe(500);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
  });

  test('[GAP] missing shapes key -> actual: 500 (crashes on "for...of shapes")', async () => {
    // Table expects 400 Bad Request, but "for (const shape of shapes)" throws
    // a TypeError when shapes is undefined — there's no Array.isArray check.
    const client = makeClient({ existingProject: null });
    pool.connect.mockResolvedValueOnce(client);

    const res = await request(app)
      .post('/sync/upload')
      .send({ project: { local_id: 'local-10', name: 'No Shapes Key' }, roomObjects: [], furnitureItems: [] });

    expect(res.status).toBe(500);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
  });

  // ---------- Note ----------
  // "Invalid user JWT -> 401 Unauthorized" is enforced by auth_middleware.js
  // (router.use(authMiddleware)) before uploadProject() ever runs. It's
  // mocked to always succeed here so this suite tests uploadProject() in
  // isolation — that case belongs in a dedicated auth_middleware test.
});
