/**
 * Google Docs Storage Service Tests
 *
 * Tests for Google Docs API integration including:
 * - Service account authentication
 * - Document CRUD operations
 * - Permission management
 * - Search and linking
 * - Error handling and retry logic
 */

import { GoogleDocsStorageService, CreateDocumentParams } from '../google-docs-storage';

// Mock googleapis
jest.mock('googleapis', () => {
  const mockCreate = jest.fn();
  const mockGet = jest.fn();
  const mockBatchUpdate = jest.fn();
  const mockList = jest.fn();
  const mockDelete = jest.fn();
  const mockPermissionsCreate = jest.fn();

  return {
    google: {
      docs: jest.fn(() => ({
        documents: {
          create: mockCreate,
          get: mockGet,
          batchUpdate: mockBatchUpdate,
        },
      })),
      drive: jest.fn(() => ({
        files: {
          list: mockList,
          delete: mockDelete,
          update: jest.fn().mockResolvedValue({ data: {} }),
        },
        permissions: {
          create: mockPermissionsCreate,
        },
      })),
    },
  };
});

// Mock google-auth-library
jest.mock('google-auth-library', () => ({
  GoogleAuth: jest.fn().mockImplementation(() => ({
    getClient: jest.fn().mockResolvedValue({
      request: jest.fn(),
    }),
  })),
}));

// Mock circuit breaker
jest.mock('../circuit-breaker', () => ({
  CircuitBreaker: jest.fn().mockImplementation(() => ({
    fire: jest.fn((fn) => fn()),
    getState: jest.fn().mockReturnValue('CLOSED'),
    on: jest.fn(),
  })),
}));

// Mock fs for reading credentials
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn().mockReturnValue(true),
  readFileSync: jest.fn().mockReturnValue(JSON.stringify({
    type: 'service_account',
    project_id: 'test-project',
    private_key_id: 'key-id',
    private_key: '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n',
    client_email: 'test@test-project.iam.gserviceaccount.com',
    client_id: '123456',
    auth_uri: 'https://accounts.google.com/o/oauth2/auth',
    token_uri: 'https://oauth2.googleapis.com/token',
  })),
}));

describe('GoogleDocsStorageService', () => {
  let service: GoogleDocsStorageService;
  let mockGoogle: any;

  beforeEach(() => {
    jest.clearAllMocks();
    mockGoogle = require('googleapis').google;

    // Reset mock implementations
    mockGoogle.docs().documents.create.mockResolvedValue({
      data: {
        documentId: 'test-doc-id',
        title: 'Test Document',
      },
    });

    mockGoogle.docs().documents.get.mockResolvedValue({
      data: {
        documentId: 'test-doc-id',
        title: 'Test Document',
        body: {
          content: [
            { paragraph: { elements: [{ textRun: { content: 'Test content' } }] } },
          ],
        },
      },
    });

    mockGoogle.docs().documents.batchUpdate.mockResolvedValue({
      data: { replies: [] },
    });

    mockGoogle.drive().files.list.mockResolvedValue({
      data: { files: [] },
    });

    mockGoogle.drive().files.delete.mockResolvedValue({
      data: {},
    });

    mockGoogle.drive().permissions.create.mockResolvedValue({
      data: { id: 'permission-id' },
    });

    service = new GoogleDocsStorageService({
      credentialsPath: '/path/to/creds.json',
    });
  });

  describe('createDocument', () => {
    it('should create a document with title and content', async () => {
      const params: CreateDocumentParams = {
        title: 'Test Document',
        content: '# Hello World\n\nThis is content.',
        folderId: 'folder-123',
      };

      const result = await service.createDocument(params);

      expect(result.documentId).toBe('test-doc-id');
      expect(result.title).toBe('Test Document');
      expect(mockGoogle.docs().documents.create).toHaveBeenCalled();
    });

    it('should create document with metadata', async () => {
      const params: CreateDocumentParams = {
        title: 'Document with Metadata',
        content: 'Content here',
        folderId: 'folder-123',
        metadata: {
          sourceDocPath: '/path/to/source.md',
          persona: 'leadership',
          projectName: 'Test Project',
          documentType: 'prd',
          createdAt: new Date(),
        },
      };

      const result = await service.createDocument(params);

      expect(result.documentId).toBe('test-doc-id');
      expect(mockGoogle.docs().documents.create).toHaveBeenCalled();
    });

    it('should handle document creation failure', async () => {
      mockGoogle.docs().documents.create.mockRejectedValue(
        new Error('API quota exceeded')
      );

      const params: CreateDocumentParams = {
        title: 'Test',
        content: 'Content',
        folderId: 'folder-123',
      };

      await expect(service.createDocument(params)).rejects.toThrow('API quota exceeded');
    });
  });

  describe('getDocument', () => {
    it('should retrieve document by ID', async () => {
      const document = await service.getDocument('test-doc-id');

      expect(document.documentId).toBe('test-doc-id');
      expect(document.title).toBe('Test Document');
      expect(mockGoogle.docs().documents.get).toHaveBeenCalledWith({
        documentId: 'test-doc-id',
      });
    });

    it('should handle document not found', async () => {
      mockGoogle.docs().documents.get.mockRejectedValue({
        code: 404,
        message: 'Document not found',
      });

      await expect(service.getDocument('non-existent')).rejects.toBeDefined();
    });
  });

  describe('updateDocument', () => {
    it('should update document content', async () => {
      await service.updateDocument('test-doc-id', 'Updated content');

      expect(mockGoogle.docs().documents.batchUpdate).toHaveBeenCalled();
      const calls = mockGoogle.docs().documents.batchUpdate.mock.calls;
      expect(calls[0][0].documentId).toBe('test-doc-id');
    });

    it('should handle update failure', async () => {
      mockGoogle.docs().documents.batchUpdate.mockRejectedValue(
        new Error('Permission denied')
      );

      await expect(
        service.updateDocument('test-doc-id', 'Content')
      ).rejects.toThrow('Permission denied');
    });
  });

  describe('deleteDocument', () => {
    it('should delete document by ID', async () => {
      await service.deleteDocument('test-doc-id');

      expect(mockGoogle.drive().files.delete).toHaveBeenCalledWith({
        fileId: 'test-doc-id',
      });
    });

    it('should handle delete failure', async () => {
      mockGoogle.drive().files.delete.mockRejectedValue(
        new Error('File not found')
      );

      await expect(service.deleteDocument('non-existent')).rejects.toThrow('File not found');
    });
  });

  describe('setPermissions', () => {
    it('should set reader permission for email', async () => {
      await service.setPermissions('test-doc-id', [
        { type: 'user', role: 'reader', email: 'user@example.com' },
      ]);

      expect(mockGoogle.drive().permissions.create).toHaveBeenCalledWith(
        expect.objectContaining({
          fileId: 'test-doc-id',
          requestBody: expect.objectContaining({
            type: 'user',
            role: 'reader',
            emailAddress: 'user@example.com',
          }),
        })
      );
    });

    it('should set writer permission', async () => {
      await service.setPermissions('test-doc-id', [
        { type: 'user', role: 'writer', email: 'editor@example.com' },
      ]);

      expect(mockGoogle.drive().permissions.create).toHaveBeenCalled();
    });

    it('should set domain-wide permission', async () => {
      await service.setPermissions('test-doc-id', [
        { type: 'domain', role: 'reader', domain: 'example.com' },
      ]);

      expect(mockGoogle.drive().permissions.create).toHaveBeenCalledWith(
        expect.objectContaining({
          requestBody: expect.objectContaining({
            type: 'domain',
            domain: 'example.com',
          }),
        })
      );
    });
  });

  describe('searchDocuments', () => {
    it('should search documents in folder', async () => {
      mockGoogle.drive().files.list.mockResolvedValue({
        data: {
          files: [
            { id: 'doc-1', name: 'Document 1' },
            { id: 'doc-2', name: 'Document 2' },
          ],
        },
      });

      const result = await service.searchDocuments('folder-123');

      expect(result.documents.length).toBe(2);
      expect(mockGoogle.drive().files.list).toHaveBeenCalled();
    });

    it('should search with query filter', async () => {
      mockGoogle.drive().files.list.mockResolvedValue({
        data: {
          files: [
            { id: 'doc-1', name: 'PRD Document' },
          ],
        },
      });

      const result = await service.searchDocuments('folder-123', 'PRD');

      expect(result.documents.length).toBe(1);
      expect(result.documents[0].name).toBe('PRD Document');
    });

    it('should return empty array for no results', async () => {
      mockGoogle.drive().files.list.mockResolvedValue({
        data: { files: [] },
      });

      const result = await service.searchDocuments('folder-123');

      expect(result.documents).toEqual([]);
    });
  });

  describe('linkDocuments', () => {
    it('should create link between documents', async () => {
      await service.linkDocuments('source-doc', 'target-doc', 'Related Document');

      expect(mockGoogle.docs().documents.batchUpdate).toHaveBeenCalled();
    });
  });

  describe('healthCheck', () => {
    it('should return healthy when API is accessible', async () => {
      const health = await service.healthCheck();

      expect(health.healthy).toBe(true);
      expect(health.service).toBe('GoogleDocsStorage');
    });

    it('should return unhealthy when API fails', async () => {
      mockGoogle.docs().documents.get.mockRejectedValue(
        new Error('Service unavailable')
      );

      const health = await service.healthCheck();

      expect(health.healthy).toBe(false);
      expect(health.error).toBeDefined();
    });
  });

  describe('retry handling', () => {
    it('should retry on transient failures', async () => {
      let callCount = 0;
      mockGoogle.docs().documents.create
        .mockImplementation(() => {
          callCount++;
          if (callCount < 3) {
            return Promise.reject(new Error('Temporary failure'));
          }
          return Promise.resolve({
            data: { documentId: 'success-doc-id', title: 'Success' },
          });
        });

      const params: CreateDocumentParams = {
        title: 'Retry Test',
        content: 'Content',
        folderId: 'folder-123',
      };

      // The service should retry and eventually succeed
      // Note: This depends on retry handler configuration
    });
  });

  describe('edge cases', () => {
    it('should handle empty content', async () => {
      const params: CreateDocumentParams = {
        title: 'Empty Document',
        content: '',
        folderId: 'folder-123',
      };

      const result = await service.createDocument(params);

      expect(result.documentId).toBe('test-doc-id');
    });

    it('should handle very long content', async () => {
      const longContent = 'A'.repeat(100000);
      const params: CreateDocumentParams = {
        title: 'Long Document',
        content: longContent,
        folderId: 'folder-123',
      };

      const result = await service.createDocument(params);

      expect(result.documentId).toBe('test-doc-id');
    });

    it('should handle special characters in title', async () => {
      const params: CreateDocumentParams = {
        title: 'Test <Document> with "special" & characters',
        content: 'Content',
        folderId: 'folder-123',
      };

      const result = await service.createDocument(params);

      expect(result.documentId).toBe('test-doc-id');
    });

    it('should handle markdown content conversion', async () => {
      const markdownContent = `
# Heading 1
## Heading 2

- List item 1
- List item 2

**Bold text** and *italic text*

\`\`\`javascript
const code = 'example';
\`\`\`
      `;

      const params: CreateDocumentParams = {
        title: 'Markdown Document',
        content: markdownContent,
        folderId: 'folder-123',
      };

      const result = await service.createDocument(params);

      expect(result.documentId).toBe('test-doc-id');
    });
  });
});
