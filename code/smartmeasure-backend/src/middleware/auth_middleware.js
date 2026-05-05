const jwt = require('jsonwebtoken');

// This function runs before any protected route
// It checks if the request has a valid JWT token
function authMiddleware(req, res, next) {

  // Token comes in the header like: Authorization: Bearer eyJhbGci...
  const authHeader = req.headers['authorization'];

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token provided. Please login.' });
  }

  // Extract just the token part after "Bearer "
  const token = authHeader.split(' ')[1];

  try {
    // Verify the token using our secret key
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // Attach user info to the request so routes can use it
    // After this, any route can access req.user.userId and req.user.email
    req.user = decoded;

    // Continue to the actual route
    next();

  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token. Please login again.' });
  }
}

module.exports = authMiddleware;