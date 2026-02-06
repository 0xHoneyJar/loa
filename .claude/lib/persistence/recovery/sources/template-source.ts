/**
 * Template-based recovery source (last-resort fallback).
 *
 * Restores from a set of pre-defined template files.
 */

import type { IRecoverySource } from "../recovery-source.js";

export class TemplateRecoverySource implements IRecoverySource {
  readonly name = "template";

  constructor(private readonly templates: Map<string, Buffer>) {}

  async isAvailable(): Promise<boolean> {
    return this.templates.size > 0;
  }

  async restore(): Promise<Map<string, Buffer> | null> {
    return new Map(this.templates);
  }
}
