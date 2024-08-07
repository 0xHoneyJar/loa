import BoardSection from "@/components/board/board-section";
import Footer from "@/components/footer";
import HeroSection from "@/components/hero/hero-section";
import { basehub } from "basehub";

export default async function Home() {
  const {
    partners: { partners },
  } = await basehub({ cache: "no-store" }).query({
    partners: {
      partners: {
        items: {
          _title: true,
          logo: true,
          partner: true,
          startDate: true,
          twitter: true,
        },
      },
    },
  });

  const {
    perks: { perks },
  } = await basehub({ cache: "no-store" }).query({
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

  return (
    <div>
      <HeroSection />
      <BoardSection
        partners={partners.items}
        community={community}
        perks={perks.items}
      />
      <Footer />
    </div>
  );
}
