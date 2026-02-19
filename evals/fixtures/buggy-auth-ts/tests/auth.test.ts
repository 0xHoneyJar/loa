import { register, login, validateToken, refreshToken } from '../src/auth';

describe('register', () => {
  it('should create a user', () => {
    const user = register('test@example.com', 'password123');
    expect(user.id).toBeDefined();
    expect(user.email).toBe('test@example.com');
  });
});

describe('login', () => {
  it('should authenticate with correct password', () => {
    const user = register('test@example.com', 'password123');
    expect(login(user, 'password123')).toBe(true);
  });

  it('should reject wrong password', () => {
    const user = register('test@example.com', 'password123');
    expect(login(user, 'wrong')).toBe(false);
  });
});

describe('validateToken', () => {
  it('should validate after login', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    expect(validateToken(user)).toBe(true);
  });
});

describe('refreshToken', () => {
  it('should refresh token after valid login', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    const originalToken = user.token;
    const newToken = refreshToken(user);
    expect(newToken).not.toBeNull();
    expect(newToken).not.toBe(originalToken);
    expect(user.token).toBe(newToken);
  });

  it('should return null when no login has occurred', () => {
    const user = register('test@example.com', 'password123');
    // No login — user has no token
    const result = refreshToken(user);
    expect(result).toBeNull();
  });

  it('should return null for expired token', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    // Manually expire the token
    user.tokenExpiry = Date.now() - 1000;
    const result = refreshToken(user);
    expect(result).toBeNull();
  });

  it('should update token expiry on refresh', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    const expiryBefore = user.tokenExpiry!;
    // Small delay to ensure Date.now() advances
    const newToken = refreshToken(user);
    expect(newToken).not.toBeNull();
    expect(user.tokenExpiry).toBeGreaterThanOrEqual(expiryBefore);
  });
});
