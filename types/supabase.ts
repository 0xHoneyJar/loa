export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      addresses: {
        Row: {
          address: string | null
          amount: number | null
          created_at: string
          dailyAllowanceRate: number | null
          id: number
          index: number | null
          root_id: number | null
        }
        Insert: {
          address?: string | null
          amount?: number | null
          created_at?: string
          dailyAllowanceRate?: number | null
          id?: number
          index?: number | null
          root_id?: number | null
        }
        Update: {
          address?: string | null
          amount?: number | null
          created_at?: string
          dailyAllowanceRate?: number | null
          id?: number
          index?: number | null
          root_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "public_addresses_root_id_fkey"
            columns: ["root_id"]
            isOneToOne: false
            referencedRelation: "roots"
            referencedColumns: ["id"]
          },
        ]
      }
      agg_data: {
        Row: {
          address: string | null
          amounts: string | null
          tokenids: string | null
        }
        Insert: {
          address?: string | null
          amounts?: string | null
          tokenids?: string | null
        }
        Update: {
          address?: string | null
          amounts?: string | null
          tokenids?: string | null
        }
        Relationships: []
      }
      angry_list: {
        Row: {
          address: string | null
          created_at: string
          id: number
          signature: string | null
          solana_address: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          id?: number
          signature?: string | null
          solana_address?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          id?: number
          signature?: string | null
          solana_address?: string | null
        }
        Relationships: []
      }
      angry_wl: {
        Row: {
          address: string
        }
        Insert: {
          address: string
        }
        Update: {
          address?: string
        }
        Relationships: []
      }
      apr_week2_quest: {
        Row: {
          address: string | null
          amount: number | null
          tokenid: string | null
        }
        Insert: {
          address?: string | null
          amount?: number | null
          tokenid?: string | null
        }
        Update: {
          address?: string | null
          amount?: number | null
          tokenid?: string | null
        }
        Relationships: []
      }
      apr_week2_twitter_quest: {
        Row: {
          address: string | null
          amount: number | null
          tokenid: string | null
        }
        Insert: {
          address?: string | null
          amount?: number | null
          tokenid?: string | null
        }
        Update: {
          address?: string | null
          amount?: number | null
          tokenid?: string | null
        }
        Relationships: []
      }
      badges: {
        Row: {
          created_at: string
          eligibility: string
          id: number
          reward: number
          title: string
        }
        Insert: {
          created_at?: string
          eligibility: string
          id: number
          reward: number
          title: string
        }
        Update: {
          created_at?: string
          eligibility?: string
          id?: number
          reward?: number
          title?: string
        }
        Relationships: []
      }
      badges_holders: {
        Row: {
          address: string
          amount: string
          tokenid: string
        }
        Insert: {
          address: string
          amount: string
          tokenid: string
        }
        Update: {
          address?: string
          amount?: string
          tokenid?: string
        }
        Relationships: []
      }
      badges_mainnet: {
        Row: {
          address: string
          amounts: number[]
          created_at: string
          id: number
          index: number
          is_hc_holder: boolean
          proof: string[]
          root: string
          token_ids: number[]
        }
        Insert: {
          address: string
          amounts: number[]
          created_at?: string
          id?: number
          index: number
          is_hc_holder: boolean
          proof: string[]
          root: string
          token_ids: number[]
        }
        Update: {
          address?: string
          amounts?: number[]
          created_at?: string
          id?: number
          index?: number
          is_hc_holder?: boolean
          proof?: string[]
          root?: string
          token_ids?: number[]
        }
        Relationships: []
      }
      badges_miss_fix: {
        Row: {
          address: string
          amounts: string
          tokenids: string
        }
        Insert: {
          address: string
          amounts: string
          tokenids: string
        }
        Update: {
          address?: string
          amounts?: string
          tokenids?: string
        }
        Relationships: []
      }
      badges_snapshot_2: {
        Row: {
          address: string
          allocations: string
          amounts: string
          index: string
          proof: string
          tokenids: string
        }
        Insert: {
          address: string
          allocations: string
          amounts: string
          index: string
          proof: string
          tokenids: string
        }
        Update: {
          address?: string
          allocations?: string
          amounts?: string
          index?: string
          proof?: string
          tokenids?: string
        }
        Relationships: []
      }
      badges_snapshot_20240307: {
        Row: {
          address: string | null
          allocations: string | null
          amounts: string | null
          index: string | null
          proof: string | null
          tokenids: string | null
        }
        Insert: {
          address?: string | null
          allocations?: string | null
          amounts?: string | null
          index?: string | null
          proof?: string | null
          tokenids?: string | null
        }
        Update: {
          address?: string | null
          allocations?: string | null
          amounts?: string | null
          index?: string | null
          proof?: string | null
          tokenids?: string | null
        }
        Relationships: []
      }
      badges_snapshot_april_week2: {
        Row: {
          address: string
          amounts: string
          index: string
          proof: string
          tokenids: string
        }
        Insert: {
          address: string
          amounts: string
          index: string
          proof: string
          tokenids: string
        }
        Update: {
          address?: string
          amounts?: string
          index?: string
          proof?: string
          tokenids?: string
        }
        Relationships: []
      }
      badges_snapshot_backup: {
        Row: {
          address: string | null
          allocations: string | null
          amounts: string | null
          index: string | null
          proof: string | null
          tokenids: string | null
        }
        Insert: {
          address?: string | null
          allocations?: string | null
          amounts?: string | null
          index?: string | null
          proof?: string | null
          tokenids?: string | null
        }
        Update: {
          address?: string | null
          allocations?: string | null
          amounts?: string | null
          index?: string | null
          proof?: string | null
          tokenids?: string | null
        }
        Relationships: []
      }
      badges_snapshot_mainnet: {
        Row: {
          address: string
          amount: number
          created_at: string
          id: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Insert: {
          address: string
          amount: number
          created_at?: string
          id?: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Update: {
          address?: string
          amount?: number
          created_at?: string
          id?: number
          index?: number
          proof?: string[]
          root?: string
          token_id?: number
        }
        Relationships: []
      }
      badges_snapshot_migration: {
        Row: {
          address: string
          amount: number
          created_at: string
          id: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Insert: {
          address: string
          amount: number
          created_at?: string
          id?: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Update: {
          address?: string
          amount?: number
          created_at?: string
          id?: number
          index?: number
          proof?: string[]
          root?: string
          token_id?: number
        }
        Relationships: []
      }
      badges_snapshot_v2: {
        Row: {
          address: string
          amount: number
          created_at: string
          id: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Insert: {
          address: string
          amount: number
          created_at?: string
          id?: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Update: {
          address?: string
          amount?: number
          created_at?: string
          id?: number
          index?: number
          proof?: string[]
          root?: string
          token_id?: number
        }
        Relationships: []
      }
      badges_snapshot_v2_duplicate: {
        Row: {
          address: string
          amount: number
          created_at: string
          id: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Insert: {
          address: string
          amount: number
          created_at?: string
          id?: number
          index: number
          proof: string[]
          root: string
          token_id: number
        }
        Update: {
          address?: string
          amount?: number
          created_at?: string
          id?: number
          index?: number
          proof?: string[]
          root?: string
          token_id?: number
        }
        Relationships: []
      }
      badges_snapshot_week3: {
        Row: {
          address: string
          amounts: string
          index: string
          proof: string
          tokenids: string
        }
        Insert: {
          address: string
          amounts: string
          index: string
          proof: string
          tokenids: string
        }
        Update: {
          address?: string
          amounts?: string
          index?: string
          proof?: string
          tokenids?: string
        }
        Relationships: []
      }
      badges_snapshot_week3_part: {
        Row: {
          address: string | null
          amounts: string | null
          index: string | null
          proof: string | null
          tokenids: string | null
        }
        Insert: {
          address?: string | null
          amounts?: string | null
          index?: string | null
          proof?: string | null
          tokenids?: string | null
        }
        Update: {
          address?: string | null
          amounts?: string | null
          index?: string | null
          proof?: string | null
          tokenids?: string | null
        }
        Relationships: []
      }
      badges_type: {
        Row: {
          announce_url: string | null
          comment: string | null
          id: string
          name: string
        }
        Insert: {
          announce_url?: string | null
          comment?: string | null
          id: string
          name: string
        }
        Update: {
          announce_url?: string | null
          comment?: string | null
          id?: string
          name?: string
        }
        Relationships: []
      }
      berabaddies_form: {
        Row: {
          address: string | null
          created_at: string
          discord: string | null
          email: string | null
          find_method: string | null
          future_suggestions: string | null
          id: number
          insta: string | null
          shirt_size: string | null
          twitter: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          discord?: string | null
          email?: string | null
          find_method?: string | null
          future_suggestions?: string | null
          id?: number
          insta?: string | null
          shirt_size?: string | null
          twitter?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          discord?: string | null
          email?: string | null
          find_method?: string | null
          future_suggestions?: string | null
          id?: number
          insta?: string | null
          shirt_size?: string | null
          twitter?: string | null
        }
        Relationships: []
      }
      berabaddies_irl_questers: {
        Row: {
          address: string
          created_at: string
          id: number
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
        }
        Relationships: []
      }
      bot_exposer: {
        Row: {
          address: string
          created_at: string
        }
        Insert: {
          address: string
          created_at?: string
        }
        Update: {
          address?: string
          created_at?: string
        }
        Relationships: []
      }
      campaigns: {
        Row: {
          cronScheduleId: string | null
          description: string
          image: string
          logo: string | null
          partnerName: string | null
          quests: Json
          reward: string
          slug: string
          title: string
        }
        Insert: {
          cronScheduleId?: string | null
          description: string
          image: string
          logo?: string | null
          partnerName?: string | null
          quests: Json
          reward: string
          slug: string
          title: string
        }
        Update: {
          cronScheduleId?: string | null
          description?: string
          image?: string
          logo?: string | null
          partnerName?: string | null
          quests?: Json
          reward?: string
          slug?: string
          title?: string
        }
        Relationships: []
      }
      dict: {
        Row: {
          create_at: string | null
          create_by: string | null
          desc: string | null
          key: string
          kind: string
          value: string | null
        }
        Insert: {
          create_at?: string | null
          create_by?: string | null
          desc?: string | null
          key: string
          kind: string
          value?: string | null
        }
        Update: {
          create_at?: string | null
          create_by?: string | null
          desc?: string | null
          key?: string
          kind?: string
          value?: string | null
        }
        Relationships: []
      }
      discord_role: {
        Row: {
          address: string
          id: string
        }
        Insert: {
          address: string
          id: string
        }
        Update: {
          address?: string
          id?: string
        }
        Relationships: []
      }
      drip_history: {
        Row: {
          id: string
          last_dripped: number
        }
        Insert: {
          id: string
          last_dripped: number
        }
        Update: {
          id?: string
          last_dripped?: number
        }
        Relationships: []
      }
      drip_snapshot: {
        Row: {
          address: string
          amount: string
          created_at: string
          index: string
          proof: string[] | null
        }
        Insert: {
          address: string
          amount: string
          created_at?: string
          index: string
          proof?: string[] | null
        }
        Update: {
          address?: string
          amount?: string
          created_at?: string
          index?: string
          proof?: string[] | null
        }
        Relationships: []
      }
      drip_snapshot_v2: {
        Row: {
          address: string
          amount: string
          created_at: string
          id: number
        }
        Insert: {
          address: string
          amount: string
          created_at?: string
          id?: number
        }
        Update: {
          address?: string
          amount?: string
          created_at?: string
          id?: number
        }
        Relationships: []
      }
      dumplicate_address: {
        Row: {
          address: string | null
          cc: number | null
        }
        Insert: {
          address?: string | null
          cc?: number | null
        }
        Update: {
          address?: string | null
          cc?: number | null
        }
        Relationships: []
      }
      farcaster_questers: {
        Row: {
          address: string
          created_at: string
          farcaster_id: number | null
          id: number
          quest_name: string
        }
        Insert: {
          address: string
          created_at?: string
          farcaster_id?: number | null
          id?: number
          quest_name: string
        }
        Update: {
          address?: string
          created_at?: string
          farcaster_id?: number | null
          id?: number
          quest_name?: string
        }
        Relationships: []
      }
      faucet_snapshot: {
        Row: {
          address: string
          amount: string
          index: string
          proof: string
        }
        Insert: {
          address: string
          amount: string
          index: string
          proof: string
        }
        Update: {
          address?: string
          amount?: string
          index?: string
          proof?: string
        }
        Relationships: []
      }
      fren_snapshot: {
        Row: {
          address: string
          amount: string
          index: string
          proof: string
        }
        Insert: {
          address: string
          amount: string
          index: string
          proof: string
        }
        Update: {
          address?: string
          amount?: string
          index?: string
          proof?: string
        }
        Relationships: []
      }
      fren_test: {
        Row: {
          address: string
          amount: string
          index: string
          proof: string
        }
        Insert: {
          address: string
          amount: string
          index: string
          proof: string
        }
        Update: {
          address?: string
          amount?: string
          index?: string
          proof?: string
        }
        Relationships: []
      }
      hc_snapshot_raffle: {
        Row: {
          balance: number
          wallet: string
        }
        Insert: {
          balance: number
          wallet: string
        }
        Update: {
          balance?: number
          wallet?: string
        }
        Relationships: []
      }
      help_em_up_badge: {
        Row: {
          created_at: string
          id: string
        }
        Insert: {
          created_at?: string
          id: string
        }
        Update: {
          created_at?: string
          id?: string
        }
        Relationships: []
      }
      henlo_holders: {
        Row: {
          address: string
          amount: number | null
          tokenid: string
        }
        Insert: {
          address: string
          amount?: number | null
          tokenid: string
        }
        Update: {
          address?: string
          amount?: number | null
          tokenid?: string
        }
        Relationships: []
      }
      honey_bluffer_badge: {
        Row: {
          created_at: string
          id: string
        }
        Insert: {
          created_at?: string
          id: string
        }
        Update: {
          created_at?: string
          id?: string
        }
        Relationships: []
      }
      hungrybera_holders: {
        Row: {
          address: string
          created_at: string
        }
        Insert: {
          address: string
          created_at?: string
        }
        Update: {
          address?: string
          created_at?: string
        }
        Relationships: []
      }
      ivx_quest: {
        Row: {
          created_at: string
          id: number
          portfolioAddress: string
          userAddress: string
        }
        Insert: {
          created_at?: string
          id?: number
          portfolioAddress: string
          userAddress: string
        }
        Update: {
          created_at?: string
          id?: number
          portfolioAddress?: string
          userAddress?: string
        }
        Relationships: []
      }
      live_sessions: {
        Row: {
          address: string
          created_at: string
          id: number
          is_active: boolean
          last_active: string | null
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
          is_active?: boolean
          last_active?: string | null
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
          is_active?: boolean
          last_active?: string | null
        }
        Relationships: []
      }
      meme1: {
        Row: {
          id: string
        }
        Insert: {
          id: string
        }
        Update: {
          id?: string
        }
        Relationships: []
      }
      meme2: {
        Row: {
          address: string
        }
        Insert: {
          address: string
        }
        Update: {
          address?: string
        }
        Relationships: []
      }
      missed_badges_type: {
        Row: {
          address: string
          amount: string | null
          tokenid: string
        }
        Insert: {
          address: string
          amount?: string | null
          tokenid: string
        }
        Update: {
          address?: string
          amount?: string | null
          tokenid?: string
        }
        Relationships: []
      }
      missed_badges_type_20240306: {
        Row: {
          address: string | null
          amount: string | null
          tokenid: string | null
        }
        Insert: {
          address?: string | null
          amount?: string | null
          tokenid?: string | null
        }
        Update: {
          address?: string | null
          amount?: string | null
          tokenid?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          address: string
          created_at: string
          id: number
          referral_code: string | null
          twitter: string | null
          username: string | null
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
          referral_code?: string | null
          twitter?: string | null
          username?: string | null
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
          referral_code?: string | null
          twitter?: string | null
          username?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "public_profiles_referral_code_fkey"
            columns: ["referral_code"]
            isOneToOne: true
            referencedRelation: "referral_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      proof_root: {
        Row: {
          comment: string | null
          create_at: string
          created_by: string
          encode_values: string
          root: string
          tree: string
        }
        Insert: {
          comment?: string | null
          create_at?: string
          created_by: string
          encode_values: string
          root: string
          tree: string
        }
        Update: {
          comment?: string | null
          create_at?: string
          created_by?: string
          encode_values?: string
          root?: string
          tree?: string
        }
        Relationships: []
      }
      quest_progress: {
        Row: {
          address: string
          quest_name: string
          tracked_steps: Json
          twitter_id: string | null
          voted_for: string | null
        }
        Insert: {
          address: string
          quest_name: string
          tracked_steps?: Json
          twitter_id?: string | null
          voted_for?: string | null
        }
        Update: {
          address?: string
          quest_name?: string
          tracked_steps?: Json
          twitter_id?: string | null
          voted_for?: string | null
        }
        Relationships: []
      }
      quest_punter: {
        Row: {
          wallet: string
        }
        Insert: {
          wallet: string
        }
        Update: {
          wallet?: string
        }
        Relationships: []
      }
      quests: {
        Row: {
          admins: string | null
          campaignName: string | null
          created_at: string
          cronScheduleId: string | null
          description: string
          disabled: boolean | null
          endTime: number
          farcasterSteps: Json[] | null
          id: number
          image: string
          link: string | null
          logo: string | null
          onchainConfig: Json | null
          partnerName: string | null
          paused: boolean
          prerequisites: string | null
          questPaths: Json | null
          requiredNFTs: string | null
          requiredQuests: string | null
          reward: string
          slug: string
          startTime: number
          steps: Json[] | null
          supportedChains: number[] | null
          title: string
          type: string
        }
        Insert: {
          admins?: string | null
          campaignName?: string | null
          created_at?: string
          cronScheduleId?: string | null
          description: string
          disabled?: boolean | null
          endTime: number
          farcasterSteps?: Json[] | null
          id?: number
          image: string
          link?: string | null
          logo?: string | null
          onchainConfig?: Json | null
          partnerName?: string | null
          paused?: boolean
          prerequisites?: string | null
          questPaths?: Json | null
          requiredNFTs?: string | null
          requiredQuests?: string | null
          reward: string
          slug: string
          startTime: number
          steps?: Json[] | null
          supportedChains?: number[] | null
          title: string
          type?: string
        }
        Update: {
          admins?: string | null
          campaignName?: string | null
          created_at?: string
          cronScheduleId?: string | null
          description?: string
          disabled?: boolean | null
          endTime?: number
          farcasterSteps?: Json[] | null
          id?: number
          image?: string
          link?: string | null
          logo?: string | null
          onchainConfig?: Json | null
          partnerName?: string | null
          paused?: boolean
          prerequisites?: string | null
          questPaths?: Json | null
          requiredNFTs?: string | null
          requiredQuests?: string | null
          reward?: string
          slug?: string
          startTime?: number
          steps?: Json[] | null
          supportedChains?: number[] | null
          title?: string
          type?: string
        }
        Relationships: []
      }
      quests_duplicate: {
        Row: {
          admins: string | null
          created_at: string
          cronScheduleId: string | null
          description: string
          disabled: boolean | null
          endTime: number
          farcasterSteps: Json[] | null
          id: number
          image: string
          link: string | null
          logo: string | null
          onchainConfig: Json | null
          partnerName: string | null
          paused: boolean
          prerequisites: string | null
          questPaths: Json | null
          requiredQuests: string | null
          reward: string
          slug: string
          startTime: number
          steps: Json[] | null
          supportedChains: number[] | null
          title: string
          type: string
        }
        Insert: {
          admins?: string | null
          created_at?: string
          cronScheduleId?: string | null
          description: string
          disabled?: boolean | null
          endTime: number
          farcasterSteps?: Json[] | null
          id?: number
          image: string
          link?: string | null
          logo?: string | null
          onchainConfig?: Json | null
          partnerName?: string | null
          paused?: boolean
          prerequisites?: string | null
          questPaths?: Json | null
          requiredQuests?: string | null
          reward: string
          slug: string
          startTime: number
          steps?: Json[] | null
          supportedChains?: number[] | null
          title: string
          type?: string
        }
        Update: {
          admins?: string | null
          created_at?: string
          cronScheduleId?: string | null
          description?: string
          disabled?: boolean | null
          endTime?: number
          farcasterSteps?: Json[] | null
          id?: number
          image?: string
          link?: string | null
          logo?: string | null
          onchainConfig?: Json | null
          partnerName?: string | null
          paused?: boolean
          prerequisites?: string | null
          questPaths?: Json | null
          requiredQuests?: string | null
          reward?: string
          slug?: string
          startTime?: number
          steps?: Json[] | null
          supportedChains?: number[] | null
          title?: string
          type?: string
        }
        Relationships: []
      }
      quests_multiple_rewards: {
        Row: {
          admins: string | null
          created_at: string
          description: string
          disabled: boolean | null
          endTime: number
          farcasterSteps: Json[] | null
          id: number
          image: string
          link: string | null
          logo: string | null
          onchainConfig: Json | null
          optionSteps: Json | null
          partnerName: string | null
          paused: boolean | null
          prerequisites: string | null
          reward: number[]
          slug: string
          startTime: number
          steps: Json[] | null
          supportedChains: number[] | null
          title: string
          type: string
        }
        Insert: {
          admins?: string | null
          created_at?: string
          description: string
          disabled?: boolean | null
          endTime: number
          farcasterSteps?: Json[] | null
          id?: number
          image: string
          link?: string | null
          logo?: string | null
          onchainConfig?: Json | null
          optionSteps?: Json | null
          partnerName?: string | null
          paused?: boolean | null
          prerequisites?: string | null
          reward: number[]
          slug: string
          startTime: number
          steps?: Json[] | null
          supportedChains?: number[] | null
          title: string
          type?: string
        }
        Update: {
          admins?: string | null
          created_at?: string
          description?: string
          disabled?: boolean | null
          endTime?: number
          farcasterSteps?: Json[] | null
          id?: number
          image?: string
          link?: string | null
          logo?: string | null
          onchainConfig?: Json | null
          optionSteps?: Json | null
          partnerName?: string | null
          paused?: boolean | null
          prerequisites?: string | null
          reward?: number[]
          slug?: string
          startTime?: number
          steps?: Json[] | null
          supportedChains?: number[] | null
          title?: string
          type?: string
        }
        Relationships: []
      }
      quests_test: {
        Row: {
          admins: string | null
          created_at: string
          description: string
          disabled: boolean | null
          endTime: number
          farcasterSteps: Json[] | null
          id: number
          image: string
          link: string | null
          logo: string | null
          partnerName: string | null
          reward: number
          slug: string
          startTime: number
          steps: Json[] | null
          title: string
          type: string
        }
        Insert: {
          admins?: string | null
          created_at?: string
          description: string
          disabled?: boolean | null
          endTime: number
          farcasterSteps?: Json[] | null
          id?: number
          image: string
          link?: string | null
          logo?: string | null
          partnerName?: string | null
          reward: number
          slug: string
          startTime: number
          steps?: Json[] | null
          title: string
          type?: string
        }
        Update: {
          admins?: string | null
          created_at?: string
          description?: string
          disabled?: boolean | null
          endTime?: number
          farcasterSteps?: Json[] | null
          id?: number
          image?: string
          link?: string | null
          logo?: string | null
          partnerName?: string | null
          reward?: number
          slug?: string
          startTime?: number
          steps?: Json[] | null
          title?: string
          type?: string
        }
        Relationships: []
      }
      QueueBoost: {
        Row: {
          amount: number | null
          blocknumber: number | null
          blocktime: string
          sender: string | null
          txhash: string
          validator: string | null
        }
        Insert: {
          amount?: number | null
          blocknumber?: number | null
          blocktime: string
          sender?: string | null
          txhash: string
          validator?: string | null
        }
        Update: {
          amount?: number | null
          blocknumber?: number | null
          blocktime?: string
          sender?: string | null
          txhash?: string
          validator?: string | null
        }
        Relationships: []
      }
      raffle_submissions: {
        Row: {
          address: string
          created_at: string
          id: number
          num_tickets: number
          raffle_name: string
          signature: string | null
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
          num_tickets: number
          raffle_name: string
          signature?: string | null
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
          num_tickets?: number
          raffle_name?: string
          signature?: string | null
        }
        Relationships: []
      }
      raffle_submissions_duplicate: {
        Row: {
          address: string
          created_at: string
          id: number
          num_tickets: number
          raffle_name: string
          signature: string | null
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
          num_tickets: number
          raffle_name: string
          signature?: string | null
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
          num_tickets?: number
          raffle_name?: string
          signature?: string | null
        }
        Relationships: []
      }
      raffle_winners: {
        Row: {
          address: string | null
          created_at: string | null
          id: number
          prize: string | null
          raffle_name: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string | null
          id?: number
          prize?: string | null
          raffle_name?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string | null
          id?: number
          prize?: string | null
          raffle_name?: string | null
        }
        Relationships: []
      }
      raffles: {
        Row: {
          contact: string | null
          created_at: string
          description: string | null
          endTime: number
          id: number
          image: string
          logo: string | null
          partnerName: string | null
          paused: boolean
          prizes: Json[]
          qualifiedUsers: Json[]
          slug: string
          snapshotTime: number
          startTime: number
          ticketCronScheduleId: string | null
          title: string
          website: string | null
          winnerCronScheduleId: string | null
        }
        Insert: {
          contact?: string | null
          created_at?: string
          description?: string | null
          endTime: number
          id?: number
          image: string
          logo?: string | null
          partnerName?: string | null
          paused?: boolean
          prizes: Json[]
          qualifiedUsers: Json[]
          slug: string
          snapshotTime: number
          startTime: number
          ticketCronScheduleId?: string | null
          title: string
          website?: string | null
          winnerCronScheduleId?: string | null
        }
        Update: {
          contact?: string | null
          created_at?: string
          description?: string | null
          endTime?: number
          id?: number
          image?: string
          logo?: string | null
          partnerName?: string | null
          paused?: boolean
          prizes?: Json[]
          qualifiedUsers?: Json[]
          slug?: string
          snapshotTime?: number
          startTime?: number
          ticketCronScheduleId?: string | null
          title?: string
          website?: string | null
          winnerCronScheduleId?: string | null
        }
        Relationships: []
      }
      raffles_duplicate: {
        Row: {
          contact: string | null
          created_at: string
          description: string | null
          endTime: number
          id: number
          image: string
          logo: string | null
          partnerName: string | null
          paused: boolean
          prizes: Json[]
          qualifiedUsers: Json[]
          slug: string
          snapshotTime: number
          startTime: number
          ticketCronScheduleId: string | null
          title: string
          website: string | null
          winnerCronScheduleId: string | null
        }
        Insert: {
          contact?: string | null
          created_at?: string
          description?: string | null
          endTime: number
          id?: number
          image: string
          logo?: string | null
          partnerName?: string | null
          paused?: boolean
          prizes: Json[]
          qualifiedUsers: Json[]
          slug: string
          snapshotTime: number
          startTime: number
          ticketCronScheduleId?: string | null
          title: string
          website?: string | null
          winnerCronScheduleId?: string | null
        }
        Update: {
          contact?: string | null
          created_at?: string
          description?: string | null
          endTime?: number
          id?: number
          image?: string
          logo?: string | null
          partnerName?: string | null
          paused?: boolean
          prizes?: Json[]
          qualifiedUsers?: Json[]
          slug?: string
          snapshotTime?: number
          startTime?: number
          ticketCronScheduleId?: string | null
          title?: string
          website?: string | null
          winnerCronScheduleId?: string | null
        }
        Relationships: []
      }
      referral_codes: {
        Row: {
          code: string
          created_at: string
          id: number
          quest_name: string | null
          user_address: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: number
          quest_name?: string | null
          user_address: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: number
          quest_name?: string | null
          user_address?: string
        }
        Relationships: [
          {
            foreignKeyName: "public_referral_codes_user_address_fkey"
            columns: ["user_address"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["address"]
          },
        ]
      }
      referrals: {
        Row: {
          created_at: string
          id: number
          quest_name: string | null
          referee_user_address: string
          referral_code: string
        }
        Insert: {
          created_at?: string
          id?: number
          quest_name?: string | null
          referee_user_address: string
          referral_code: string
        }
        Update: {
          created_at?: string
          id?: number
          quest_name?: string | null
          referee_user_address?: string
          referral_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "public_referrals_referral_code_fkey"
            columns: ["referral_code"]
            isOneToOne: false
            referencedRelation: "referral_codes"
            referencedColumns: ["code"]
          },
        ]
      }
      roots: {
        Row: {
          created_at: string
          id: number
          root_hash: string | null
        }
        Insert: {
          created_at?: string
          id?: number
          root_hash?: string | null
        }
        Update: {
          created_at?: string
          id?: number
          root_hash?: string | null
        }
        Relationships: []
      }
      shell_survivor_badge: {
        Row: {
          address: string
          created_at: string
          id: number
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
        }
        Relationships: []
      }
      solana_nft_snapshot: {
        Row: {
          address: string
        }
        Insert: {
          address: string
        }
        Update: {
          address?: string
        }
        Relationships: []
      }
      tmp_double_address: {
        Row: {
          address: string | null
          created_at: string | null
          id: number | null
          row_num: number | null
          signature: string | null
          solana_address: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string | null
          id?: number | null
          row_num?: number | null
          signature?: string | null
          solana_address?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string | null
          id?: number | null
          row_num?: number | null
          signature?: string | null
          solana_address?: string | null
        }
        Relationships: []
      }
      tmp_twitter_quests: {
        Row: {
          address: string | null
        }
        Insert: {
          address?: string | null
        }
        Update: {
          address?: string | null
        }
        Relationships: []
      }
      tmp_week3_quest: {
        Row: {
          address: string | null
          amount: number | null
          tokenid: string | null
        }
        Insert: {
          address?: string | null
          amount?: number | null
          tokenid?: string | null
        }
        Update: {
          address?: string | null
          amount?: number | null
          tokenid?: string | null
        }
        Relationships: []
      }
      twitter_questers: {
        Row: {
          address: string
          created_at: string
          id: number
          quest_name: string
          twitter_id: string | null
          voted_for: string | null
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
          quest_name: string
          twitter_id?: string | null
          voted_for?: string | null
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
          quest_name?: string
          twitter_id?: string | null
          voted_for?: string | null
        }
        Relationships: []
      }
      unlinked_twitter_accounts: {
        Row: {
          created_at: string
          id: number
          twitter: string
          unlinked_at: string
        }
        Insert: {
          created_at?: string
          id?: number
          twitter: string
          unlinked_at: string
        }
        Update: {
          created_at?: string
          id?: number
          twitter?: string
          unlinked_at?: string
        }
        Relationships: []
      }
      user_tokens: {
        Row: {
          access_token: string
          expires_at: string | null
          id: string
          provider: string
          refresh_token: string | null
          user_id: string | null
        }
        Insert: {
          access_token: string
          expires_at?: string | null
          id?: string
          provider: string
          refresh_token?: string | null
          user_id?: string | null
        }
        Update: {
          access_token?: string
          expires_at?: string | null
          id?: string
          provider?: string
          refresh_token?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          created_at: string | null
          discord_id: string | null
          discord_username: string | null
          id: string
          referral_code: string | null
          twitter_id: string | null
          twitter_username: string | null
        }
        Insert: {
          created_at?: string | null
          discord_id?: string | null
          discord_username?: string | null
          id?: string
          referral_code?: string | null
          twitter_id?: string | null
          twitter_username?: string | null
        }
        Update: {
          created_at?: string | null
          discord_id?: string | null
          discord_username?: string | null
          id?: string
          referral_code?: string | null
          twitter_id?: string | null
          twitter_username?: string | null
        }
        Relationships: []
      }
      verified_retweets_apiology: {
        Row: {
          address: string
          created_at: string
          id: number
        }
        Insert: {
          address: string
          created_at?: string
          id?: number
        }
        Update: {
          address?: string
          created_at?: string
          id?: number
        }
        Relationships: []
      }
      wallets_claim_tbera: {
        Row: {
          wallets: string
        }
        Insert: {
          wallets: string
        }
        Update: {
          wallets?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_badges_leaderboard: {
        Args: Record<PropertyKey, never>
        Returns: {
          address: string
          count: number
        }[]
      }
      get_distinct_root_token_id: {
        Args: Record<PropertyKey, never>
        Returns: {
          root: string
          token_id: number
        }[]
      }
      get_distinct_root_token_id_migration: {
        Args: Record<PropertyKey, never>
        Returns: {
          root: string
          token_id: number
        }[]
      }
      get_distinct_root_token_id_migration_v2: {
        Args: Record<PropertyKey, never>
        Returns: {
          root: string
          token_id: number
        }[]
      }
      get_referrals_for_address:
        | {
            Args: {
              input_address: string
            }
            Returns: {
              id: number
              created_at: string
              referral_code: string
              referee_user_address: string
              quest_name: string
            }[]
          }
        | {
            Args: {
              input_address: string
              input_quest_name: string
            }
            Returns: {
              id: number
              created_at: string
              referral_code: string
              referee_user_address: string
              quest_name: string
            }[]
          }
      get_total_participants_for_farcaster_quest: {
        Args: {
          quest_name_param: string
        }
        Returns: number
      }
      get_total_participants_for_referral_quest: {
        Args: {
          quest_name_param: string
        }
        Returns: number
      }
      get_total_participants_for_twitter_quest: {
        Args: {
          quest_name_param: string
        }
        Returns: number
      }
      get_total_tickets: {
        Args: {
          arg: string
        }
        Returns: number
      }
      get_unique_badge_ids_v2: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: number
        }[]
      }
      get_unique_quest_names: {
        Args: Record<PropertyKey, never>
        Returns: {
          quest_name: string
        }[]
      }
      get_unique_raffle_names: {
        Args: Record<PropertyKey, never>
        Returns: {
          raffle_name: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type PublicSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (PublicSchema["Tables"] & PublicSchema["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (PublicSchema["Tables"] &
        PublicSchema["Views"])
    ? (PublicSchema["Tables"] &
        PublicSchema["Views"])[PublicTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof PublicSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof PublicSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof Database }
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof PublicSchema["CompositeTypes"]
    ? PublicSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never
