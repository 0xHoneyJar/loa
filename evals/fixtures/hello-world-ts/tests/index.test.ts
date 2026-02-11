import { greet, add, isEven } from '../src/index';

describe('greet', () => {
  it('should greet by name', () => {
    expect(greet('World')).toBe('Hello, World!');
  });
});

describe('add', () => {
  it('should add two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });
});

describe('isEven', () => {
  it('should return true for even numbers', () => {
    expect(isEven(4)).toBe(true);
  });
  it('should return false for odd numbers', () => {
    expect(isEven(3)).toBe(false);
  });
});
