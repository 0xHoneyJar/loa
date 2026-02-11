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
