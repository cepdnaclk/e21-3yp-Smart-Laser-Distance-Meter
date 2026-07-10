// tests/auth.register.test.js
// Unit tests for POST /auth/register
// Author: Chamod S.A.R. (E/21/065)
//
// Mocks: PostgreSQL pool (src/db/db.js) and bcryptjs — no real DB or hashing runs.

const request = require('supertest');
const express = require('express');

jest.mock('../src/db/db', () => ({
  query: jest.fn(),
}));
jest.mock('bcryptjs', () => ({
  hash: jest.fn(),
  compare: jest.fn(),
}));

const pool = require('../src/db/db');
const bcrypt = require('bcryptjs');
const authRoutes = require('../src/routes/auth');

const app = express();
app.use(express.json());
app.use('/auth', authRoutes);

describe('POST /auth/register', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ---------- Equivalence classes ----------

  test('valid input -> 201 Created', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] }) // no existing user
      .mockResolvedValueOnce({ rows: [{ id: 1, email: 'test@gmail.com' }] }); // insert
    bcrypt.hash.mockResolvedValueOnce('hashedpassword');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'test@gmail.com', password: 'pass123' });

    expect(res.status).toBe(201);
    expect(res.body.user).toEqual({ id: 1, email: 'test@gmail.com' });
  });

  test('missing email -> 400 Bad Request', async () => {
    const res = await request(app)
      .post('/auth/register')
      .send({ password: 'pass123' });

    expect(res.status).toBe(400);
  });

  test('missing password -> 400 Bad Request', async () => {
    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'test@gmail.com' });

    expect(res.status).toBe(400);
  });

  test('both email and password missing -> 400 Bad Request', async () => {
    const res = await request(app).post('/auth/register').send({});
    expect(res.status).toBe(400);
  });

  test('duplicate email -> 409 Conflict', async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ id: 5 }] }); // existing user found

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'existing@gmail.com', password: 'pass123' });

    expect(res.status).toBe(409);
  });

  // ---------- Boundary value analysis (password length, min = 6) ----------

  test('password exactly 6 chars (on boundary) -> 201 Created', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: 2, email: 'a@gmail.com' }] });
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'a@gmail.com', password: 'abc123' });

    expect(res.status).toBe(201);
  });

  test('password 5 chars (just below minimum) -> 400 Bad Request', async () => {
    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'a@gmail.com', password: 'abc12' });

    expect(res.status).toBe(400);
  });

  test('password 7 chars (just above minimum) -> 201 Created', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: 3, email: 'b@gmail.com' }] });
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'b@gmail.com', password: 'abc1234' });

    expect(res.status).toBe(201);
  });

  test('empty string password -> 400 Bad Request', async () => {
    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'a@gmail.com', password: '' });

    expect(res.status).toBe(400);
  });

  test('very long email (255 chars) -> 201 Created (no max length check exists)', async () => {
    const longEmail = 'a'.repeat(246) + '@gmail.com'; // 256 chars total
    pool.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: 7, email: longEmail }] });
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: longEmail, password: 'pass123' });

    expect(res.status).toBe(201);
  });

  // ---------- Error / negative cases ----------

  test('database error on duplicate-check query -> 500 Internal Server Error', async () => {
    pool.query.mockRejectedValueOnce(new Error('DB connection failed'));

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'x@gmail.com', password: 'pass123' });

    expect(res.status).toBe(500);
  });

  test('database error on insert query -> 500 Internal Server Error', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] }) // duplicate check passes
      .mockRejectedValueOnce(new Error('Insert failed')); // insert fails
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'y@gmail.com', password: 'pass123' });

    expect(res.status).toBe(500);
  });

  // ---------- KNOWN GAPS — code does not currently enforce these ----------
  // Your Step 1 table says these should return 400, but register() has no
  // email-format validation and no whitespace trimming, so they currently
  // pass through as 201. Flag this in your Step 3 peer review as a bug
  // the test suite caught, or update auth.js to add validation.

  test('[GAP] invalid email format is currently accepted -> actual: 201', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: 8, email: 'notanemail' }] });
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'notanemail', password: 'pass123' });

    expect(res.status).toBe(201); // table expected 400 — code doesn't check this
  });

  test('[GAP] email with spaces is currently accepted -> actual: 201', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: 9, email: ' test @gmail.com ' }] });
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: ' test @gmail.com ', password: 'pass123' });

    expect(res.status).toBe(201); // table expected 400 — code doesn't check this
  });

  test('[GAP] password of only spaces (length >= 6) is currently accepted -> actual: 201', async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: 10, email: 'c@gmail.com' }] });
    bcrypt.hash.mockResolvedValueOnce('hashed');

    const res = await request(app)
      .post('/auth/register')
      .send({ email: 'c@gmail.com', password: '      ' });

    expect(res.status).toBe(201); // table expected 400 — code doesn't check this
  });
});
