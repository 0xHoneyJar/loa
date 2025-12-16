/**
 * RACI Generation Service
 *
 * Sprint 6 - Task 6.3: RACI Generation Service
 *
 * Auto-generates RACI (Responsible, Accountable, Consulted, Informed) matrices
 * for product launches and initiatives based on sprint plans and team structure.
 *
 * Features:
 * - Analyze sprint plan for tasks
 * - Analyze team structure from Linear
 * - Generate RACI assignments based on task types
 * - Create Google Doc with full matrix
 * - Tenant isolation for multi-tenancy
 */

import { logger } from '../utils/logger';
import { getCurrentTenant } from './tenant-context';
import { TieredCache } from './tiered-cache';

// =============================================================================
// Types
// =============================================================================

export type RACIRole = 'R' | 'A' | 'C' | 'I' | '';

export interface RACIMatrix {
  product: string;
  initiative: string;
  generatedAt: Date;
  tasks: RACITask[];
  teamMembers: TeamMember[];
  assignments: RACIAssignment[][];
  summary: RACISummary;
}

export interface RACITask {
  id: string;
  name: string;
  description: string;
  category: TaskCategory;
  priority: 'high' | 'medium' | 'low';
}

export type TaskCategory =
  | 'development'
  | 'design'
  | 'marketing'
  | 'operations'
  | 'security'
  | 'testing'
  | 'documentation'
  | 'deployment'
  | 'communication';

export interface TeamMember {
  id: string;
  name: string;
  role: TeamRole;
  department: string;
}

export type TeamRole =
  | 'engineer'
  | 'designer'
  | 'product_manager'
  | 'marketing_lead'
  | 'devops'
  | 'security'
  | 'qa'
  | 'executive'
  | 'stakeholder';

export interface RACIAssignment {
  taskId: string;
  memberId: string;
  role: RACIRole;
  reason?: string;
}

export interface RACISummary {
  totalTasks: number;
  totalMembers: number;
  responsibleCount: number;
  accountableCount: number;
  consultedCount: number;
  informedCount: number;
  unassignedTasks: string[];
  overloadedMembers: OverloadedMember[];
}

export interface OverloadedMember {
  memberId: string;
  name: string;
  responsibleCount: number;
  accountableCount: number;
}

export interface RACIGenerationOptions {
  /** Include detailed reasons for assignments */
  includeReasons?: boolean;
  /** Use template for specific launch type */
  template?: RACITemplate;
  /** Custom task list (overrides sprint plan parsing) */
  customTasks?: RACITask[];
  /** Custom team members (overrides Linear lookup) */
  customTeam?: TeamMember[];
  /** Use cached result if available */
  useCache?: boolean;
}

export type RACITemplate =
  | 'product_launch'
  | 'feature_release'
  | 'security_release'
  | 'marketing_campaign'
  | 'custom';

export interface LinearTeamData {
  id: string;
  name: string;
  members?: { nodes: Array<{ id: string; name: string; displayName?: string }> };
}

export interface SprintPlanData {
  tasks: Array<{
    name: string;
    description?: string;
    assignee?: string;
    labels?: string[];
  }>;
}

export interface GoogleDocsClientInterface {
  createDocument(title: string, content: string): Promise<{ documentId: string; url: string }>;
}

export interface LinearClientInterface {
  getTeam(teamId: string): Promise<LinearTeamData | null>;
}

// =============================================================================
// RACI Generation Service
// =============================================================================

export class RACIService {
  private static instance: RACIService;
  private cache: TieredCache;
  private googleDocsClient: GoogleDocsClientInterface | null = null;
  private linearClient: LinearClientInterface | null = null;

  constructor() {
    this.cache = TieredCache.getInstance();
  }

  /**
   * Get singleton instance
   */
  static getInstance(): RACIService {
    if (!RACIService.instance) {
      RACIService.instance = new RACIService();
    }
    return RACIService.instance;
  }

  /**
   * Inject Google Docs client
   */
  setGoogleDocsClient(client: GoogleDocsClientInterface): void {
    this.googleDocsClient = client;
  }

  /**
   * Inject Linear client
   */
  setLinearClient(client: LinearClientInterface): void {
    this.linearClient = client;
  }

  // ===========================================================================
  // Main Generation Methods
  // ===========================================================================

  /**
   * Generate RACI matrix for a product initiative
   */
  async generateRACIMatrix(
    product: string,
    initiative: string,
    options: RACIGenerationOptions = {}
  ): Promise<RACIMatrix> {
    const tenant = getCurrentTenant();
    const cacheKey = `raci:${product}:${initiative}`;

    logger.info('Generating RACI matrix', {
      tenantId: tenant.tenantId,
      product,
      initiative,
      template: options.template ?? 'product_launch',
    });

    // Check cache if enabled
    if (options.useCache !== false) {
      try {
        const cached = await this.cache.get<RACIMatrix>(tenant.tenantId, cacheKey);
        if (cached) {
          logger.debug('RACI matrix retrieved from cache', { product, initiative });
          return cached;
        }
      } catch (error) {
        logger.warn('Cache lookup failed for RACI', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    try {
      // Get tasks (from options or generate from template)
      const tasks = options.customTasks ?? this.generateTasks(initiative, options.template);

      // Get team members (from options or from Linear)
      const teamMembers = options.customTeam ?? await this.getTeamMembers(product);

      // Generate assignments
      const assignments = this.generateAssignments(tasks, teamMembers, options);

      // Calculate summary
      const summary = this.calculateSummary(tasks, teamMembers, assignments);

      const matrix: RACIMatrix = {
        product,
        initiative,
        generatedAt: new Date(),
        tasks,
        teamMembers,
        assignments,
        summary,
      };

      // Cache the result (10 min TTL)
      try {
        await this.cache.set(tenant.tenantId, cacheKey, matrix, 600);
      } catch (error) {
        logger.warn('Failed to cache RACI matrix', {
          error: error instanceof Error ? error.message : String(error),
        });
      }

      logger.info('RACI matrix generated', {
        tenantId: tenant.tenantId,
        product,
        initiative,
        taskCount: tasks.length,
        memberCount: teamMembers.length,
      });

      return matrix;
    } catch (error) {
      logger.error('Failed to generate RACI matrix', {
        error: error instanceof Error ? error.message : String(error),
        product,
        initiative,
      });
      throw error;
    }
  }

  /**
   * Generate RACI matrix and create Google Doc
   */
  async generateRACIDocument(
    product: string,
    initiative: string,
    options: RACIGenerationOptions = {}
  ): Promise<{ matrix: RACIMatrix; documentUrl: string }> {
    const tenant = getCurrentTenant();

    // Generate the matrix
    const matrix = await this.generateRACIMatrix(product, initiative, options);

    // Create Google Doc if client is available
    if (!this.googleDocsClient) {
      logger.warn('Google Docs client not configured, skipping document creation');
      return { matrix, documentUrl: '' };
    }

    try {
      const title = `RACI Matrix: ${product} - ${initiative}`;
      const content = this.formatMatrixAsDocument(matrix);

      const { url } = await this.googleDocsClient.createDocument(title, content);

      logger.info('RACI document created', {
        tenantId: tenant.tenantId,
        product,
        initiative,
        documentUrl: url,
      });

      return { matrix, documentUrl: url };
    } catch (error) {
      logger.error('Failed to create RACI document', {
        error: error instanceof Error ? error.message : String(error),
      });
      return { matrix, documentUrl: '' };
    }
  }

  // ===========================================================================
  // Task Generation
  // ===========================================================================

  /**
   * Generate tasks based on initiative type and template
   */
  private generateTasks(initiative: string, template?: RACITemplate): RACITask[] {
    const templateType = template ?? 'product_launch';
    const templates = this.getTaskTemplates();

    const templateTasks = templates[templateType] ?? templates.product_launch;

    return templateTasks.map((t, index) => ({
      id: `task-${index + 1}`,
      name: t.name.replace('{initiative}', initiative),
      description: t.description.replace('{initiative}', initiative),
      category: t.category,
      priority: t.priority,
    }));
  }

  /**
   * Get task templates for different initiative types
   */
  private getTaskTemplates(): Record<RACITemplate, Array<{
    name: string;
    description: string;
    category: TaskCategory;
    priority: 'high' | 'medium' | 'low';
  }>> {
    return {
      product_launch: [
        { name: 'Define launch goals', description: 'Define success metrics and goals for {initiative}', category: 'development', priority: 'high' },
        { name: 'Technical implementation', description: 'Complete technical implementation for {initiative}', category: 'development', priority: 'high' },
        { name: 'Security review', description: 'Security audit and review for {initiative}', category: 'security', priority: 'high' },
        { name: 'QA testing', description: 'Quality assurance testing for {initiative}', category: 'testing', priority: 'high' },
        { name: 'Documentation', description: 'Create user and technical documentation', category: 'documentation', priority: 'medium' },
        { name: 'Marketing materials', description: 'Create marketing content and materials', category: 'marketing', priority: 'medium' },
        { name: 'Announcement post', description: 'Write and review announcement post', category: 'communication', priority: 'medium' },
        { name: 'Social media campaign', description: 'Plan and execute social media campaign', category: 'marketing', priority: 'medium' },
        { name: 'Deploy to production', description: 'Deploy {initiative} to production', category: 'deployment', priority: 'high' },
        { name: 'Monitor and support', description: 'Post-launch monitoring and support', category: 'operations', priority: 'high' },
      ],
      feature_release: [
        { name: 'Feature specification', description: 'Define feature requirements for {initiative}', category: 'development', priority: 'high' },
        { name: 'UI/UX design', description: 'Design user interface for {initiative}', category: 'design', priority: 'high' },
        { name: 'Implementation', description: 'Develop feature for {initiative}', category: 'development', priority: 'high' },
        { name: 'Code review', description: 'Review code changes', category: 'development', priority: 'high' },
        { name: 'Testing', description: 'Test feature functionality', category: 'testing', priority: 'high' },
        { name: 'Documentation update', description: 'Update documentation', category: 'documentation', priority: 'medium' },
        { name: 'Release notes', description: 'Write release notes', category: 'communication', priority: 'low' },
        { name: 'Deployment', description: 'Deploy to production', category: 'deployment', priority: 'high' },
      ],
      security_release: [
        { name: 'Vulnerability assessment', description: 'Assess security vulnerability', category: 'security', priority: 'high' },
        { name: 'Patch development', description: 'Develop security patch', category: 'development', priority: 'high' },
        { name: 'Security review', description: 'Review patch for completeness', category: 'security', priority: 'high' },
        { name: 'Regression testing', description: 'Test for regressions', category: 'testing', priority: 'high' },
        { name: 'Emergency deployment', description: 'Deploy security patch', category: 'deployment', priority: 'high' },
        { name: 'Incident communication', description: 'Communicate with stakeholders', category: 'communication', priority: 'high' },
        { name: 'Post-mortem', description: 'Conduct post-mortem analysis', category: 'operations', priority: 'medium' },
      ],
      marketing_campaign: [
        { name: 'Campaign strategy', description: 'Define campaign strategy for {initiative}', category: 'marketing', priority: 'high' },
        { name: 'Content creation', description: 'Create campaign content', category: 'marketing', priority: 'high' },
        { name: 'Design assets', description: 'Create visual assets', category: 'design', priority: 'high' },
        { name: 'Technical setup', description: 'Set up tracking and analytics', category: 'development', priority: 'medium' },
        { name: 'Partner coordination', description: 'Coordinate with partners', category: 'communication', priority: 'medium' },
        { name: 'Campaign launch', description: 'Launch campaign', category: 'marketing', priority: 'high' },
        { name: 'Performance monitoring', description: 'Monitor campaign performance', category: 'operations', priority: 'medium' },
        { name: 'Results report', description: 'Create campaign results report', category: 'documentation', priority: 'low' },
      ],
      custom: [],
    };
  }

  // ===========================================================================
  // Team Member Handling
  // ===========================================================================

  /**
   * Get team members from Linear or generate defaults
   */
  private async getTeamMembers(product: string): Promise<TeamMember[]> {
    const tenant = getCurrentTenant();

    // Try to get from Linear
    if (this.linearClient && tenant.credentials?.linear?.teamId) {
      try {
        const team = await this.linearClient.getTeam(tenant.credentials.linear.teamId);
        if (team?.members?.nodes) {
          return team.members.nodes.map((m, index) => ({
            id: m.id,
            name: m.displayName ?? m.name,
            role: this.inferRoleFromName(m.name),
            department: this.inferDepartmentFromRole(this.inferRoleFromName(m.name)),
          }));
        }
      } catch (error) {
        logger.warn('Failed to fetch Linear team, using defaults', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Return default team structure
    return this.getDefaultTeamMembers();
  }

  /**
   * Get default team members for MVP
   */
  private getDefaultTeamMembers(): TeamMember[] {
    return [
      { id: 'pm-1', name: 'Product Manager', role: 'product_manager', department: 'Product' },
      { id: 'eng-1', name: 'Lead Engineer', role: 'engineer', department: 'Engineering' },
      { id: 'eng-2', name: 'Senior Engineer', role: 'engineer', department: 'Engineering' },
      { id: 'design-1', name: 'Designer', role: 'designer', department: 'Design' },
      { id: 'mkt-1', name: 'Marketing Lead', role: 'marketing_lead', department: 'Marketing' },
      { id: 'devops-1', name: 'DevOps Engineer', role: 'devops', department: 'Engineering' },
      { id: 'qa-1', name: 'QA Engineer', role: 'qa', department: 'Engineering' },
      { id: 'exec-1', name: 'Executive Sponsor', role: 'executive', department: 'Leadership' },
    ];
  }

  /**
   * Infer role from name
   */
  private inferRoleFromName(name: string): TeamRole {
    const lowerName = name.toLowerCase();
    if (lowerName.includes('pm') || lowerName.includes('product')) return 'product_manager';
    if (lowerName.includes('design')) return 'designer';
    if (lowerName.includes('marketing')) return 'marketing_lead';
    if (lowerName.includes('devops') || lowerName.includes('ops')) return 'devops';
    if (lowerName.includes('security')) return 'security';
    if (lowerName.includes('qa') || lowerName.includes('test')) return 'qa';
    if (lowerName.includes('ceo') || lowerName.includes('cto') || lowerName.includes('exec')) return 'executive';
    return 'engineer';
  }

  /**
   * Infer department from role
   */
  private inferDepartmentFromRole(role: TeamRole): string {
    const mapping: Record<TeamRole, string> = {
      engineer: 'Engineering',
      designer: 'Design',
      product_manager: 'Product',
      marketing_lead: 'Marketing',
      devops: 'Engineering',
      security: 'Security',
      qa: 'Engineering',
      executive: 'Leadership',
      stakeholder: 'External',
    };
    return mapping[role] ?? 'Other';
  }

  // ===========================================================================
  // Assignment Generation
  // ===========================================================================

  /**
   * Generate RACI assignments
   */
  private generateAssignments(
    tasks: RACITask[],
    members: TeamMember[],
    options: RACIGenerationOptions
  ): RACIAssignment[][] {
    const assignments: RACIAssignment[][] = [];

    for (const task of tasks) {
      const taskAssignments: RACIAssignment[] = [];

      for (const member of members) {
        const role = this.determineRole(task, member);
        const assignment: RACIAssignment = {
          taskId: task.id,
          memberId: member.id,
          role,
        };

        if (options.includeReasons && role !== '') {
          assignment.reason = this.generateReason(task, member, role);
        }

        taskAssignments.push(assignment);
      }

      assignments.push(taskAssignments);
    }

    return assignments;
  }

  /**
   * Determine RACI role for a task-member pair
   */
  private determineRole(task: RACITask, member: TeamMember): RACIRole {
    const category = task.category;
    const role = member.role;

    // Role mapping rules
    const rules: Record<TaskCategory, Partial<Record<TeamRole, RACIRole>>> = {
      development: {
        engineer: 'R',
        product_manager: 'A',
        qa: 'C',
        devops: 'I',
        executive: 'I',
      },
      design: {
        designer: 'R',
        product_manager: 'A',
        engineer: 'C',
        marketing_lead: 'I',
      },
      marketing: {
        marketing_lead: 'R',
        product_manager: 'A',
        designer: 'C',
        executive: 'I',
      },
      operations: {
        devops: 'R',
        engineer: 'A',
        product_manager: 'C',
        executive: 'I',
      },
      security: {
        security: 'R',
        engineer: 'A',
        devops: 'C',
        executive: 'I',
      },
      testing: {
        qa: 'R',
        engineer: 'A',
        product_manager: 'C',
        devops: 'I',
      },
      documentation: {
        engineer: 'R',
        product_manager: 'A',
        marketing_lead: 'C',
        designer: 'I',
      },
      deployment: {
        devops: 'R',
        engineer: 'A',
        product_manager: 'C',
        executive: 'I',
      },
      communication: {
        marketing_lead: 'R',
        product_manager: 'A',
        executive: 'C',
        engineer: 'I',
      },
    };

    return rules[category]?.[role] ?? '';
  }

  /**
   * Generate reason for assignment
   */
  private generateReason(task: RACITask, member: TeamMember, role: RACIRole): string {
    const reasons: Record<RACIRole, string> = {
      'R': `${member.role} is responsible for ${task.category} tasks`,
      'A': `${member.role} is accountable for ${task.category} outcomes`,
      'C': `${member.role} provides input on ${task.category} tasks`,
      'I': `${member.role} needs to be informed about ${task.category} progress`,
      '': '',
    };
    return reasons[role];
  }

  // ===========================================================================
  // Summary Calculation
  // ===========================================================================

  /**
   * Calculate RACI summary
   */
  private calculateSummary(
    tasks: RACITask[],
    members: TeamMember[],
    assignments: RACIAssignment[][]
  ): RACISummary {
    let responsibleCount = 0;
    let accountableCount = 0;
    let consultedCount = 0;
    let informedCount = 0;
    const unassignedTasks: string[] = [];
    const memberWorkload = new Map<string, { r: number; a: number }>();

    // Initialize workload tracking
    for (const member of members) {
      memberWorkload.set(member.id, { r: 0, a: 0 });
    }

    // Count assignments
    for (let i = 0; i < assignments.length; i++) {
      const taskAssignments = assignments[i];
      let hasResponsible = false;
      let hasAccountable = false;

      for (const assignment of taskAssignments) {
        if (assignment.role === 'R') {
          responsibleCount++;
          hasResponsible = true;
          const workload = memberWorkload.get(assignment.memberId);
          if (workload) workload.r++;
        } else if (assignment.role === 'A') {
          accountableCount++;
          hasAccountable = true;
          const workload = memberWorkload.get(assignment.memberId);
          if (workload) workload.a++;
        } else if (assignment.role === 'C') {
          consultedCount++;
        } else if (assignment.role === 'I') {
          informedCount++;
        }
      }

      if (!hasResponsible || !hasAccountable) {
        unassignedTasks.push(tasks[i].id);
      }
    }

    // Find overloaded members (more than 50% of tasks)
    const threshold = Math.ceil(tasks.length * 0.5);
    const overloadedMembers: OverloadedMember[] = [];

    for (const [memberId, workload] of memberWorkload) {
      if (workload.r >= threshold || workload.a >= threshold) {
        const member = members.find((m) => m.id === memberId);
        if (member) {
          overloadedMembers.push({
            memberId,
            name: member.name,
            responsibleCount: workload.r,
            accountableCount: workload.a,
          });
        }
      }
    }

    return {
      totalTasks: tasks.length,
      totalMembers: members.length,
      responsibleCount,
      accountableCount,
      consultedCount,
      informedCount,
      unassignedTasks,
      overloadedMembers,
    };
  }

  // ===========================================================================
  // Formatting Methods
  // ===========================================================================

  /**
   * Format matrix as document content
   */
  private formatMatrixAsDocument(matrix: RACIMatrix): string {
    const lines: string[] = [];

    lines.push(`# RACI Matrix: ${matrix.product} - ${matrix.initiative}`);
    lines.push('');
    lines.push(`Generated: ${matrix.generatedAt.toISOString()}`);
    lines.push('');
    lines.push('## Legend');
    lines.push('- **R** = Responsible (does the work)');
    lines.push('- **A** = Accountable (owns the outcome)');
    lines.push('- **C** = Consulted (provides input)');
    lines.push('- **I** = Informed (kept updated)');
    lines.push('');
    lines.push('## Matrix');
    lines.push('');

    // Build table header
    const header = ['Task', ...matrix.teamMembers.map((m) => m.name)];
    lines.push(`| ${header.join(' | ')} |`);
    lines.push(`| ${header.map(() => '---').join(' | ')} |`);

    // Build table rows
    for (let i = 0; i < matrix.tasks.length; i++) {
      const task = matrix.tasks[i];
      const taskAssignments = matrix.assignments[i];
      const row = [task.name];

      for (const member of matrix.teamMembers) {
        const assignment = taskAssignments.find((a) => a.memberId === member.id);
        row.push(assignment?.role ?? '');
      }

      lines.push(`| ${row.join(' | ')} |`);
    }

    lines.push('');
    lines.push('## Summary');
    lines.push('');
    lines.push(`- Total Tasks: ${matrix.summary.totalTasks}`);
    lines.push(`- Total Team Members: ${matrix.summary.totalMembers}`);
    lines.push(`- Responsible Assignments: ${matrix.summary.responsibleCount}`);
    lines.push(`- Accountable Assignments: ${matrix.summary.accountableCount}`);
    lines.push(`- Consulted Assignments: ${matrix.summary.consultedCount}`);
    lines.push(`- Informed Assignments: ${matrix.summary.informedCount}`);

    if (matrix.summary.unassignedTasks.length > 0) {
      lines.push('');
      lines.push('### ⚠️ Unassigned Tasks');
      for (const taskId of matrix.summary.unassignedTasks) {
        const task = matrix.tasks.find((t) => t.id === taskId);
        if (task) lines.push(`- ${task.name}`);
      }
    }

    if (matrix.summary.overloadedMembers.length > 0) {
      lines.push('');
      lines.push('### ⚠️ Overloaded Members');
      for (const member of matrix.summary.overloadedMembers) {
        lines.push(`- ${member.name}: R=${member.responsibleCount}, A=${member.accountableCount}`);
      }
    }

    return lines.join('\n');
  }

  /**
   * Format matrix as Discord embed
   */
  formatMatrixForDiscord(matrix: RACIMatrix): object {
    const memberSummary = matrix.teamMembers
      .slice(0, 8)
      .map((m) => `• ${m.name} (${m.role})`)
      .join('\n');

    const taskSummary = matrix.tasks
      .slice(0, 8)
      .map((t) => `• ${t.name}`)
      .join('\n');

    return {
      title: `RACI Matrix: ${matrix.product}`,
      description: `Initiative: ${matrix.initiative}`,
      fields: [
        { name: 'Tasks', value: `${matrix.summary.totalTasks} total\n${taskSummary}${matrix.tasks.length > 8 ? '\n...' : ''}`, inline: true },
        { name: 'Team', value: `${matrix.summary.totalMembers} members\n${memberSummary}${matrix.teamMembers.length > 8 ? '\n...' : ''}`, inline: true },
        {
          name: 'Assignments',
          value: [
            `R: ${matrix.summary.responsibleCount}`,
            `A: ${matrix.summary.accountableCount}`,
            `C: ${matrix.summary.consultedCount}`,
            `I: ${matrix.summary.informedCount}`,
          ].join(' | '),
          inline: false,
        },
        {
          name: 'Issues',
          value: matrix.summary.unassignedTasks.length > 0 || matrix.summary.overloadedMembers.length > 0
            ? [
                matrix.summary.unassignedTasks.length > 0 ? `⚠️ ${matrix.summary.unassignedTasks.length} tasks need assignment` : '',
                matrix.summary.overloadedMembers.length > 0 ? `⚠️ ${matrix.summary.overloadedMembers.length} members overloaded` : '',
              ].filter(Boolean).join('\n')
            : '✅ All assignments look good',
          inline: false,
        },
      ],
      footer: { text: `Generated at ${matrix.generatedAt.toISOString()}` },
    };
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const raciService = RACIService.getInstance();
export default raciService;
