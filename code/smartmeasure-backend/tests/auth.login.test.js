// tests/auth.login.test.js
// Unit tests for POST /auth/login
// Assigned to: Chandrasiri E.M.D.D.V (E/21/068)
//
// Mocks: PostgreSQL pool (src/db/db.js), bcryptjs, jsonwebtoken.

const request = require('supertest');
const express = require('express');

jest.mock('../src/db/db', () => ({ query: jest.fn() }));
jest.mock('bcryptjs', () => ({ hash: jest.fn(), compare: jest.fn() }));
jest.mock('jsonwebtoken', () => ({ sign: jest.fn() }));

const pool = require('../src/db/db');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const authRoutes = require('../src/routes/auth');

const app = express();
app.use(express.json());
app.use('/auth', authRoutes);

describe('POST /auth/login', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.JWT_SECRET = 'test-secret';
    jwt.sign.mockReturnValue('fake.jwt.token');
  });

  // ---------- Equivalence classes ----------

  test('valid credentials -> 200 OK with JWT token', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, email: 'test@gmail.com', password_hash: 'hashed' }],
    });
    bcrypt.compare.mockResolvedValueOnce(true);

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com', password: 'pass123' });

    expect(res.status).toBe(200);
    expect(res.body.token).toBe('fake.jwt.token');
    expect(res.body.user).toEqual({ id: 1, email: 'test@gmail.com' });
  });

  test('wrong password -> 401 Unauthorized', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, email: 'test@gmail.com', password_hash: 'hashed' }],
    });
    bcrypt.compare.mockResolvedValueOnce(false);

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com', password: 'wrongpass' });

    expect(res.status).toBe(401);
  });

  test('non-existent email -> 401 Unauthorized', async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'nouser@gmail.com', password: 'pass123' });

    expect(res.status).toBe(401);
  });

  test('missing email -> 400 Bad Request', async () => {
    const res = await request(app).post('/auth/login').send({ password: 'pass123' });
    expect(res.status).toBe(400);
  });

  test('missing password -> 400 Bad Request', async () => {
    const res = await request(app).post('/auth/login').send({ email: 'test@gmail.com' });
    expect(res.status).toBe(400);
  });

  test('both fields empty -> 400 Bad Request', async () => {
    const res = await request(app).post('/auth/login').send({ email: '', password: '' });
    expect(res.status).toBe(400);
  });

  // ---------- Error / negative cases ----------

  test('database query fails -> 500 Internal Server Error', async () => {
    pool.query.mockRejectedValueOnce(new Error('DB down'));

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com', password: 'pass123' });

    expect(res.status).toBe(500);
  });

  test('JWT_SECRET missing from environment -> 500 Internal Server Error', async () => {
    delete process.env.JWT_SECRET;
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, email: 'test@gmail.com', password_hash: 'hashed' }],
    });
    bcrypt.compare.mockResolvedValueOnce(true);
    jwt.sign.mockImplementationOnce(() => {
      throw new Error('secretOrPrivateKey must have a value');
    });

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com', password: 'pass123' });

    expect(res.status).toBe(500);
  });

  // ---------- Boundary value analysis ----------

  test('password exactly matching hash -> 200 OK', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, email: 'test@gmail.com', password_hash: 'hashed' }],
    });
    bcrypt.compare.mockResolvedValueOnce(true);

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com', password: 'correctpass' });

    expect(res.status).toBe(200);
  });

  test('password one character different -> 401 Unauthorized', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, email: 'test@gmail.com', password_hash: 'hashed' }],
    });
    bcrypt.compare.mockResolvedValueOnce(false);

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com', password: 'correctpasZ' });

    expect(res.status).toBe(401);
  });

  // ---------- Notes / known gaps ----------

  test('[NOTE] email case sensitivity depends on DB collation, not app code', async () => {
    // login() runs 'SELECT * FROM users WHERE email = $1' with no LOWER()/ILIKE.
    // Whether TEST@GMAIL.COM matches a stored test@gmail.com depends entirely on
    // Postgres column collation — this can only be verified with a real DB
    // integration test, not a mocked unit test. Simulating a case-sensitive DB below.
    pool.query.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'TEST@GMAIL.COM', password: 'pass123' });

    expect(res.status).toBe(401);
  });

  test('[GAP] email with trailing space is not trimmed -> currently 401 if no exact DB match', async () => {
    // login() does not trim input, so 'test@gmail.com ' won't match a stored
    // 'test@gmail.com' unless the DB happens to have that exact value.
    pool.query.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'test@gmail.com ', password: 'pass123' });

    expect(res.status).toBe(401);
  });
});
