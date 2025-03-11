import BoardSection from "@/components/board/board-section";
import Footer from "@/components/footer";
import HeroSection from "@/components/hero/hero-section";
import { basehub } from "basehub";

export default async function Home() {
  let partnersData: any;
  let perksData: any;
  let communityData: any;

  try {
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
            status: true,
            category: true,
          },
        },
      },
    });
    partnersData = partners.items;
  } catch (e) {
    console.log(e);
  }

  try {
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
    perksData = perks.items;
  } catch (e) {
    console.log(e);
  }

  try {
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
    communityData = community;
  } catch (e) {
    console.log(e);
  }

  return (
    <div>
      <HeroSection />
      <BoardSection
        partners={partnersData || []}
        community={communityData}
        perks={perksData || []}
      />
      <Footer />
    </div>
  );
}
