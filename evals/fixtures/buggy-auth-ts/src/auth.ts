// BUG: Hardcoded JWT secret (exposed-secret)
const JWT_SECRET = "super-secret-key-12345";

interface User {
  id: string;
  email: string;
  passwordHash: string;
  token?: string;
  tokenExpiry?: number;
}

// BUG: No email validation (missing-validation)
export function register(email: string, password: string): User {
  const user: User = {
    id: Math.random().toString(36).slice(2),
    email: email,
    passwordHash: hashPassword(password),
  };
  return user;
}

export function login(user: User, password: string): boolean {
  if (hashPassword(password) !== user.passwordHash) {
    return false;
  }
  user.token = generateToken(user.id);
  user.tokenExpiry = Date.now() + 3600000;
  return true;
}

export function validateToken(user: User): boolean {
  if (!user.token || !user.tokenExpiry) {
    return false;
  }
  return user.tokenExpiry > Date.now();
}

// BUG: TOCTOU race condition (race-condition)
// Checks expiry, then refreshes — another thread could invalidate between check and refresh
export function refreshToken(user: User): string | null {
  if (!validateToken(user)) {
    return null;
  }
  // Gap between check and update allows race condition
  const newToken = generateToken(user.id);
  user.token = newToken;
  user.tokenExpiry = Date.now() + 3600000;
  return newToken;
}

function hashPassword(password: string): string {
  let hash = 0;
  for (let i = 0; i < password.length; i++) {
    const char = password.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash |= 0;
  }
  return hash.toString(16);
}

function generateToken(userId: string): string {
  return `${userId}.${Date.now()}.${Math.random().toString(36).slice(2)}`;
}
