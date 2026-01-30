# API Documentation

This document describes the REST API endpoints available in the Community Interface.

## Base URL

```
/api
```

## Endpoints

### GET /api/quests

Get the number of participants for a specific quest.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `questName` | string | Yes | The name of the quest |

**Response:**

```json
{
  "numParticipants": 150
}
```

**Implementation Details:**
- Validates `questName` using Zod schema
- Looks up quest in Supabase `quests` table
- For onchain quests (all steps are `OnchainAction`): queries GraphQL for participant count
- For offchain quests: counts entries in `quest_progress` table

**Example:**

```bash
curl "/api/quests?questName=Bitget%20Quest"
```

---

### GET /api/holders

Get the number of unique Honeycomb NFT holders.

**Response:**

```json
{
  "uniqueHolders": 5432
}
```

**Implementation Details:**
- Queries THJ Envio indexer GraphQL endpoint
- Paginates through all `UserBalance` records with `generation=0` (Honeycomb) and `balanceTotal > 0`
- Returns count of unique holder addresses
- Includes no-cache headers

**Example:**

```bash
curl "/api/holders"
```

---

### GET /api/validator

Get THJ validator statistics from Berachain mainnet.

**Response:**

```json
{
  "amountDelegated": "1234567890000000000000",
  "rewardRate": "1000000000000000",
  "rank": "15",
  "boosters": "342"
}
```

**Fields:**
- `amountDelegated`: Total BGT delegated to THJ validator (wei)
- `rewardRate`: Current reward rate
- `rank`: Validator ranking by boost amount
- `boosters`: Number of users actively boosting

**Implementation Details:**
- Queries Berachain API for validator data
- Returns data for THJ mainnet validator

**Example:**

```bash
curl "/api/validator"
```

---

### GET /api/raffles

Get the total number of raffle entries for a specific raffle.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `raffleName` | string | Yes | The name of the raffle |

**Response:**

```json
{
  "numEntries": 2500
}
```

**Error Response:**

```json
{
  "error": "Error message"
}
```

**Implementation Details:**
- Validates `raffleName` using Zod schema
- Calls Supabase RPC function `get_total_tickets`

**Example:**

```bash
curl "/api/raffles?raffleName=Weekly%20Raffle"
```

---

### POST /api/delegate

Handle delegation widget interactions.

**Implementation Details:**
- Uses `@0xhoneyjar/validator-widget` server handler
- Handles delegation operations for the THJ validator

**Note:** This endpoint is created by the validator widget library and handles its own request/response format.

---

### GET /api/ramen-ido

Get featured IDO projects from Ramen Finance.

**Response:**

```json
{
  "projects": [
    {
      "name": "Project Name",
      "...": "other project fields"
    }
  ]
}
```

**Error Response:**

```json
{
  "error": "Failed to retrieve projects"
}
```

**Implementation Details:**
- Fetches from Ramen Finance API
- Returns array of featured projects

**Example:**

```bash
curl "/api/ramen-ido"
```

---

### GET /api/kingdomly-mints

Get partner mint collections from Kingdomly.

**Response:**

```json
{
  "mints": [
    {
      "name": "Collection Name",
      "...": "other collection fields"
    }
  ]
}
```

**Error Response:**

```json
{
  "error": "Failed to retrieve mints"
}
```

**Implementation Details:**
- Requires `KINGDOMLY_MINT_API_KEY` environment variable
- Fetches from Kingdomly partner API

**Example:**

```bash
curl "/api/kingdomly-mints"
```

---

### GET /api/liquidmint-mints

Get recent NFT mints from LiquidMint platform.

**Response:**

```json
{
  "mints": [
    {
      "collection": {
        "name": "Collection Name"
      },
      "tokenId": "123",
      "createdTimestamp": "1706745600"
    }
  ]
}
```

**Error Response:**

```json
{
  "error": "Failed to retrieve mints"
}
```

**Implementation Details:**
- Queries HyperIndex GraphQL indexer
- Returns tokens from collections with launchpad IDs
- Sorted by creation timestamp (newest first)

**Example:**

```bash
curl "/api/liquidmint-mints"
```

---

## Error Handling

All endpoints follow a consistent error response format:

```json
{
  "error": "Error description"
}
```

HTTP status codes:
- `200` - Success
- `400` - Bad request (invalid parameters)
- `500` - Internal server error

## Environment Variables

Required for API functionality:

| Variable | Endpoint | Description |
|----------|----------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | /quests, /raffles | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | /quests, /raffles | Supabase anonymous key |
| `KINGDOMLY_MINT_API_KEY` | /kingdomly-mints | Kingdomly API key |
| `RPC_URL_80094` | /validator | Berachain mainnet RPC URL |

## Data Sources

| Endpoint | Data Source |
|----------|-------------|
| /quests | Supabase + THJ GraphQL |
| /holders | THJ Envio Indexer |
| /validator | Berachain API |
| /raffles | Supabase |
| /delegate | Berachain (via widget) |
| /ramen-ido | Ramen Finance API |
| /kingdomly-mints | Kingdomly API |
| /liquidmint-mints | HyperIndex GraphQL |
