# Basehub CMS Integration

This document describes how the Community Interface integrates with [Basehub](https://basehub.com/) for content management.

## Overview

Basehub is a headless CMS that provides the editorial content for the dashboard. Content is fetched server-side at request time using the Basehub SDK.

## Configuration

### Environment Variables

```
BASEHUB_TOKEN=your_basehub_token
```

### Build Integration

The Basehub CLI generates TypeScript types during the build process:

```json
{
  "scripts": {
    "build": "basehub && next build"
  }
}
```

Generated types are stored in `.basehub/` (gitignored).

## Data Models

### Partners

Ecosystem partners displayed in the dashboard.

| Field | Type | Description |
|-------|------|-------------|
| `_title` | string | Partner name |
| `logo` | string | Logo image URL |
| `partner` | string | Partner description |
| `startDate` | string | Partnership start date |
| `twitter` | string | Twitter/X profile URL |
| `status` | string | Partnership tier (platinum, gold, silver, bronze, backed, joint) |
| `category` | string | Partner category |

**Used by:**
- `components/board/new-partners.tsx` - Featured partners carousel
- `components/board/partners.tsx` - Full partners list
- `components/board/portfolio.tsx` - Portfolio view

### Perks

Community perks and benefits.

| Field | Type | Description |
|-------|------|-------------|
| `_title` | string | Perk name |
| `perks` | string | Perk description |
| `startDate` | string | Perk availability start |
| `endDate` | string | Perk expiration date |
| `link` | string | Redemption URL |
| `details` | string | Additional details |
| `partner.logo` | string | Partner logo |
| `partner.category` | string | Partner category |

**Used by:**
- `components/board/honeycomb.tsx` - Perks grid

### Community

Community content including spotlights, mints, developments, and updates.

#### Spotlight

| Field | Type | Description |
|-------|------|-------------|
| `_title` | string | Internal title |
| `title` | string | Display title |
| `description` | string | Spotlight description |
| `link` | string | External link |
| `image` | string | Featured image URL |

**Used by:**
- `components/board/spotlight.tsx`

#### Mints

| Field | Type | Description |
|-------|------|-------------|
| `_title` | string | Mint name |
| `price` | string | Mint price |
| `supply` | string | Total supply |
| `link` | string | Mint page URL |
| `image` | string | Collection image |
| `endDate` | string | Mint end date |
| `partner.logo` | string | Partner logo |
| `partner._title` | string | Partner name |

**Used by:**
- `app/mint-collection/page.tsx` - Mint collection page
- `components/explore-mint.tsx` - Mint explorer

#### Developments

| Field | Type | Description |
|-------|------|-------------|
| `_title` | string | Development name |
| `milestones.items` | array | List of milestones |
| `milestones.items._title` | string | Milestone name |
| `milestones.items.link` | string | Milestone link |

**Used by:**
- `components/board/development.tsx`

#### Updates

| Field | Type | Description |
|-------|------|-------------|
| `_title` | string | Update title |
| `description` | string | Update description |
| `link` | string | Update link |
| `image` | string | Update image |

**Used by:**
- `components/board/updates.tsx`

## Usage Examples

### Fetching Partners

```typescript
import { basehub } from "basehub";

const { partners } = await basehub({ cache: "no-store" }).query({
  partners: {
    partners: {
      items: {
        _title: true,
        logo: true,
        partner: true,
        startDate: true,
        twitter: true,
        status: true,
        category: true,
      },
    },
  },
});
```

### Fetching Perks

```typescript
const { perks } = await basehub({ cache: "no-store" }).query({
  perks: {
    perks: {
      items: {
        _title: true,
        perks: true,
        startDate: true,
        endDate: true,
        link: true,
        details: true,
        partner: {
          logo: true,
          category: true,
        },
      },
    },
  },
});
```

### Fetching Community Content

```typescript
const { community } = await basehub({ cache: "no-store" }).query({
  community: {
    spotlight: {
      _title: true,
      title: true,
      description: true,
      link: true,
      image: true,
    },
    mints: {
      items: {
        _title: true,
        price: true,
        supply: true,
        link: true,
        image: true,
        endDate: true,
        partner: {
          logo: true,
          _title: true,
        },
      },
    },
    developments: {
      items: {
        _title: true,
        milestones: {
          items: {
            _title: true,
            link: true,
          },
        },
      },
    },
    updates: {
      items: {
        _title: true,
        description: true,
        link: true,
        image: true,
      },
    },
  },
});
```

## Caching

All queries use `cache: "no-store"` to ensure fresh content on every request. For improved performance, consider implementing ISR (Incremental Static Regeneration) with `revalidate`:

```typescript
await basehub({ cache: "no-store" }).query({...})  // Current: No caching
await basehub({ next: { revalidate: 60 } }).query({...})  // Alternative: Revalidate every 60s
```

## Content Management

### Adding a New Partner

1. Log into Basehub dashboard
2. Navigate to Partners collection
3. Click "Add Partner"
4. Fill in required fields:
   - Title (partner name)
   - Logo (upload image)
   - Twitter URL
   - Status (partnership tier)
   - Category
5. Publish changes

### Adding a New Perk

1. Log into Basehub dashboard
2. Navigate to Perks collection
3. Click "Add Perk"
4. Fill in required fields:
   - Title
   - Description
   - Link
   - Start/End dates
   - Associated partner
5. Publish changes

## Troubleshooting

### Types not generating

Run `pnpm basehub` manually to regenerate types:

```bash
pnpm basehub
```

### Content not updating

Ensure you're using `cache: "no-store"` or clear the Next.js cache:

```bash
rm -rf .next
pnpm build
```

### Missing environment variable

Ensure `BASEHUB_TOKEN` is set in your `.env` file.
