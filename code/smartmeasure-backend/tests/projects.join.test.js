// tests/projects.join.test.js
// Unit tests for POST /projects/join
// Assigned to: Rashmika W.B.R. (E/21/325)
//
// Mocks: PostgreSQL pool (src/db/db.js) and the JWT auth middleware
// (req.user.userId is injected directly, since the middleware is an
// external dependency this function doesn't own).

const request = require('supertest');
const express = require('express');

jest.mock('../src/db/db', () => ({ query: jest.fn() }));
jest.mock('../src/middleware/auth_middleware', () => (req, res, next) => {
  req.user = { userId: 1 };
  next();
});

const pool = require('../src/db/db');
const projectRoutes = require('../src/routes/projects');

const app = express();
app.use(express.json());
app.use('/projects', projectRoutes);

describe('POST /projects/join', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ---------- Equivalence classes ----------

  test('valid invite code, different user -> 200 OK joined successfully', async () => {
    pool.query
      .mockResolvedValueOnce({
        rows: [{ id: 10, user_id: 2, name: 'Living Room', owner_email: 'owner@gmail.com', updated_at: new Date() }],
      })
      .mockResolvedValueOnce({ rows: [] }) // no existing collaborator row
      .mockResolvedValueOnce({}); // insert collaborator

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7P' });

    expect(res.status).toBe(200);
    expect(res.body.message).toBe('Joined successfully');
  });

  test('owner tries to join own project -> 400 Bad Request', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 10, user_id: 1, name: 'Living Room', owner_email: 'owner@gmail.com' }],
    });

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7P' });

    expect(res.status).toBe(400);
  });

  test('non-existent invite code -> 404 Not Found', async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    const res = await request(app).post('/projects/join').send({ invite_code: 'ZZZZZZZZ' });

    expect(res.status).toBe(404);
  });

  test('previously invited but not yet accepted -> 200 OK, status updated to accepted', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: 10, user_id: 2, name: 'Living Room', owner_email: 'owner@gmail.com' }] })
      .mockResolvedValueOnce({ rows: [{ id: 99, status: 'pending' }] })
      .mockResolvedValueOnce({});

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7P' });

    expect(res.status).toBe(200);
  });

  test('missing invite code -> 400 Bad Request', async () => {
    const res = await request(app).post('/projects/join').send({});
    expect(res.status).toBe(400);
  });

  // ---------- Boundary value analysis (invite code length) ----------

  test('exactly 8 characters, valid -> 200 OK', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: 11, user_id: 2, name: 'P', owner_email: 'o@gmail.com' }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({});

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7P' });

    expect(res.status).toBe(200);
  });

  test('7 characters (one short) -> 404 Not Found', async () => {
    pool.query.mockResolvedValueOnce({ rows: [] }); // no code that short exists in DB

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7' });

    expect(res.status).toBe(404);
  });

  test('9 characters (one too long) -> 404 Not Found', async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7PP' });

    expect(res.status).toBe(404);
  });

  test('lowercase code is uppercased before lookup -> 200 OK', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: 12, user_id: 2, name: 'P', owner_email: 'o@gmail.com' }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({});

    const res = await request(app).post('/projects/join').send({ invite_code: 'ab3xkq7p' });

    expect(res.status).toBe(200);
    expect(pool.query.mock.calls[0][1][0]).toBe('AB3XKQ7P'); // confirms .toUpperCase().trim() ran
  });

  test('code with surrounding spaces is trimmed before lookup -> 200 OK', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: 13, user_id: 2, name: 'P', owner_email: 'o@gmail.com' }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({});

    const res = await request(app).post('/projects/join').send({ invite_code: '  AB3XKQ7P  ' });

    expect(res.status).toBe(200);
    expect(pool.query.mock.calls[0][1][0]).toBe('AB3XKQ7P');
  });

  // ---------- Known gap ----------

  test('[GAP] already an accepted collaborator -> actual: 409 Conflict (table expected 200 upsert)', async () => {
    // Your Step 1 table lists "Already joined -> 200 OK, upsert, no duplicate",
    // but the real code returns 409 Conflict when status is already 'accepted'.
    // Flag this discrepancy in your Step 3 peer review, or update the table.
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: 10, user_id: 2, name: 'Living Room', owner_email: 'owner@gmail.com' }] })
      .mockResolvedValueOnce({ rows: [{ id: 99, status: 'accepted' }] });

    const res = await request(app).post('/projects/join').send({ invite_code: 'AB3XKQ7P' });

    expect(res.status).toBe(409);
  });

  // ---------- Note ----------
  // "Unauthenticated request, no JWT -> 401 Unauthorized" is enforced by
  // auth_middleware.js (router.use(authMiddleware)), not by joinProject()
  // itself. It's mocked to always succeed here so this suite can test
  // joinProject() in isolation — that 401 case belongs in a dedicated
  // auth_middleware unit test, not this file.
});
