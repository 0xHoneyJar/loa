# The Honey Jar - Community Interface

Community dashboard for the Berachain ecosystem, connecting users to ecosystem projects, perks, quests, and community activities.

## Features

- **Ecosystem Partners** - Browse and discover Berachain ecosystem projects
- **Perks Aggregation** - Access community perks and benefits
- **Quest Tracking** - Participate in onchain and offchain quests
- **Validator Delegation** - Delegate to THJ validator
- **NFT/Mint Portal** - Track upcoming and active mints
- **Community Spotlight** - Stay updated on developments and milestones
- **Raffle Participation** - Enter community raffles

## Getting Started

1. Clone the repository
2. Install dependencies
3. Set up environment variables from `.env.example`

```bash
pnpm install
pnpm dev
```

## Environment Variables

Required variables (see `.env.example`):

- `NEXT_PUBLIC_SUPABASE_URL` - Supabase project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` - Supabase anonymous key
- `BASEHUB_TOKEN` - Basehub CMS token
- `NEXT_PUBLIC_PRIVY_APP_ID` - Privy authentication app ID

## Tech Stack

### Core
- [Next.js 14](https://nextjs.org/) - React framework with App Router
- [TypeScript](https://www.typescriptlang.org/) - Type safety
- [Tailwind CSS](https://tailwindcss.com/) - Utility-first styling

### Web3
- [Wagmi](https://wagmi.sh/) - React hooks for Ethereum
- [Viem](https://viem.sh/) - TypeScript Ethereum library
- [Privy](https://www.privy.io/) - Wallet authentication
- [Web3Modal](https://web3modal.com/) - Wallet connection UI

### Data & Backend
- [Supabase](https://supabase.com/) - Database and authentication
- [Basehub](https://basehub.com/) - Headless CMS for content
- [Apollo Client](https://www.apollographql.com/) - GraphQL client

### UI
- [Radix UI](https://www.radix-ui.com/) - Accessible component primitives
- [Framer Motion](https://www.framer.com/motion/) - Animations
- [Lucide](https://lucide.dev/) - Icons

### State & Utilities
- [Zustand](https://github.com/pmndrs/zustand) - State management
- [Zod](https://zod.dev/) - Schema validation
- [Immer](https://github.com/immerjs/immer) - Immutable state updates

## Project Structure

```
app/           # Next.js App Router pages and API routes
components/    # React components
  ├── board/   # Dashboard section components
  ├── ui/      # Reusable UI components (shadcn/ui)
  ├── hero/    # Hero section
  └── audio/   # Audio components
actions/       # Server actions
queries/       # GraphQL queries
state/         # Zustand stores
lib/           # Utility functions and configs
constants/     # Static configuration data
abis/          # Smart contract ABIs
```

## API Routes

| Endpoint | Description |
|----------|-------------|
| `/api/quests` | Quest participation data |
| `/api/holders` | Token holder information |
| `/api/validator` | Validator statistics |
| `/api/raffles` | Raffle entries |
| `/api/delegate` | Delegation data |

## Deployment

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2FzkSoju%2Fwagmi-boiler)
