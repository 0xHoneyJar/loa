export interface IHasher {
  sha256(input: string): Promise<string>;
}
