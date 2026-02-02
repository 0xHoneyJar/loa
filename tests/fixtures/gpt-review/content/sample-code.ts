// Sample TypeScript code for testing GPT review

export interface User {
  id: string;
  name: string;
  email: string;
}

export function validateUser(user: User): boolean {
  if (!user.id || !user.name || !user.email) {
    return false;
  }
  return user.email.includes('@');
}

export async function fetchUser(id: string): Promise<User | null> {
  // Simulated API call
  return {
    id,
    name: 'Test User',
    email: 'test@example.com'
  };
}
