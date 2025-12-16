/**
 * Role Mapper Service
 *
 * Sprint 3 - Task 3.6: Role-Based Access Control
 *
 * Maps Discord roles to persona types for automatic audience detection.
 * Users with specific Discord roles automatically get summaries tailored
 * to their persona.
 *
 * Features:
 * - Discord role → persona mapping
 * - Priority handling for users with multiple roles
 * - Configurable role mappings via YAML/JSON
 * - Fallback to default persona
 */

import { GuildMember, Guild } from 'discord.js';
import { logger } from '../utils/logger';
import { PersonaType } from '../prompts/persona-prompts';
import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// =============================================================================
// Types and Interfaces
// =============================================================================

export interface RoleMapping {
  roleId: string;
  persona: PersonaType;
  priority: number; // Higher = more priority (Leadership=1 > Product=2 > Marketing=3 > DevRel=4)
}

export interface RoleMappingConfig {
  role_mappings: Record<string, PersonaType>;
  default_persona: PersonaType;
  priority_order: PersonaType[];
}

// =============================================================================
// Role Mapper Service
// =============================================================================

export class RoleMapper {
  private roleMappings: Map<string, { persona: PersonaType; priority: number }> = new Map();
  private defaultPersona: PersonaType = 'product';
  private priorityOrder: PersonaType[] = ['leadership', 'product', 'marketing', 'devrel'];
  private initialized = false;

  constructor() {
    // Initialize with environment variables or config file on first use
  }

  /**
   * Initialize the role mapper with configuration
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      // Try to load from config file
      const configLoaded = await this.loadConfigFile();

      if (!configLoaded) {
        // Fall back to environment variables
        this.loadFromEnvironment();
      }

      this.initialized = true;
      logger.info('RoleMapper initialized', {
        mappingsCount: this.roleMappings.size,
        defaultPersona: this.defaultPersona,
      });
    } catch (error) {
      logger.error('Failed to initialize RoleMapper', {
        error: error instanceof Error ? error.message : String(error),
      });
      // Use defaults if initialization fails
      this.initialized = true;
    }
  }

  /**
   * Load configuration from YAML or JSON file
   */
  private async loadConfigFile(): Promise<boolean> {
    const configPaths = [
      path.join(process.cwd(), 'config', 'role-mapping.yml'),
      path.join(process.cwd(), 'config', 'role-mapping.yaml'),
      path.join(process.cwd(), 'config', 'role-mapping.json'),
    ];

    for (const configPath of configPaths) {
      if (fs.existsSync(configPath)) {
        try {
          const content = fs.readFileSync(configPath, 'utf-8');
          let config: RoleMappingConfig;

          if (configPath.endsWith('.json')) {
            config = JSON.parse(content);
          } else {
            config = yaml.load(content) as RoleMappingConfig;
          }

          // Parse role mappings
          if (config.role_mappings) {
            Object.entries(config.role_mappings).forEach(([roleId, persona]) => {
              const priority = this.getPersonaPriority(persona, config.priority_order);
              this.roleMappings.set(roleId, { persona, priority });
            });
          }

          // Set default persona
          if (config.default_persona) {
            this.defaultPersona = config.default_persona;
          }

          // Set priority order
          if (config.priority_order) {
            this.priorityOrder = config.priority_order;
          }

          logger.info('RoleMapper config loaded from file', { configPath });
          return true;
        } catch (error) {
          logger.warn('Failed to parse role mapping config', {
            configPath,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    }

    return false;
  }

  /**
   * Load configuration from environment variables
   */
  private loadFromEnvironment(): void {
    // Environment variable format: ROLE_MAPPING_<PERSONA>=<ROLE_ID>
    // Example: ROLE_MAPPING_LEADERSHIP=1234567890
    const envMappings: Record<string, PersonaType> = {
      ROLE_MAPPING_LEADERSHIP: 'leadership',
      ROLE_MAPPING_PRODUCT: 'product',
      ROLE_MAPPING_MARKETING: 'marketing',
      ROLE_MAPPING_DEVREL: 'devrel',
    };

    Object.entries(envMappings).forEach(([envVar, persona]) => {
      const roleId = process.env[envVar];
      if (roleId) {
        const priority = this.getPersonaPriority(persona, this.priorityOrder);
        this.roleMappings.set(roleId, { persona, priority });
        logger.debug('Role mapping loaded from env', { envVar, roleId, persona });
      }
    });

    // Default persona from environment
    const defaultPersonaEnv = process.env.DEFAULT_PERSONA;
    if (defaultPersonaEnv && this.isValidPersona(defaultPersonaEnv)) {
      this.defaultPersona = defaultPersonaEnv as PersonaType;
    }

    logger.info('RoleMapper configured from environment', {
      mappingsCount: this.roleMappings.size,
      defaultPersona: this.defaultPersona,
    });
  }

  /**
   * Detect persona for a Discord guild member
   */
  async detectPersona(member: GuildMember): Promise<PersonaType> {
    await this.initialize();

    // Get user's roles
    const userRoleIds = member.roles.cache.map(role => role.id);

    // Find matching persona with highest priority
    let bestMatch: { persona: PersonaType; priority: number } | null = null;

    for (const roleId of userRoleIds) {
      const mapping = this.roleMappings.get(roleId);
      if (mapping) {
        if (!bestMatch || mapping.priority < bestMatch.priority) {
          bestMatch = mapping;
        }
      }
    }

    if (bestMatch) {
      logger.debug('Persona detected from role', {
        userId: member.id,
        persona: bestMatch.persona,
        roleCount: userRoleIds.length,
      });
      return bestMatch.persona;
    }

    logger.debug('Using default persona', {
      userId: member.id,
      defaultPersona: this.defaultPersona,
    });
    return this.defaultPersona;
  }

  /**
   * Detect persona from user ID (looks up member in guild)
   */
  async detectPersonaFromUserId(userId: string, guild: Guild): Promise<PersonaType> {
    try {
      const member = await guild.members.fetch(userId);
      return this.detectPersona(member);
    } catch (error) {
      logger.warn('Failed to fetch member for persona detection', {
        userId,
        error: error instanceof Error ? error.message : String(error),
      });
      return this.defaultPersona;
    }
  }

  /**
   * Get priority for a persona (lower number = higher priority)
   */
  private getPersonaPriority(persona: PersonaType, priorityOrder: PersonaType[]): number {
    const index = priorityOrder.indexOf(persona);
    return index >= 0 ? index + 1 : priorityOrder.length + 1;
  }

  /**
   * Check if a string is a valid persona type
   */
  private isValidPersona(value: string): value is PersonaType {
    return ['leadership', 'product', 'marketing', 'devrel'].includes(value);
  }

  /**
   * Get all configured role mappings (for debugging/display)
   */
  getRoleMappings(): Map<string, { persona: PersonaType; priority: number }> {
    return new Map(this.roleMappings);
  }

  /**
   * Get default persona
   */
  getDefaultPersona(): PersonaType {
    return this.defaultPersona;
  }

  /**
   * Add or update a role mapping at runtime
   */
  setRoleMapping(roleId: string, persona: PersonaType): void {
    const priority = this.getPersonaPriority(persona, this.priorityOrder);
    this.roleMappings.set(roleId, { persona, priority });
    logger.info('Role mapping updated', { roleId, persona, priority });
  }

  /**
   * Remove a role mapping
   */
  removeRoleMapping(roleId: string): boolean {
    const removed = this.roleMappings.delete(roleId);
    if (removed) {
      logger.info('Role mapping removed', { roleId });
    }
    return removed;
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const roleMapper = new RoleMapper();
export default roleMapper;
