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
        },
      },
    },
  });

  const { spotlight } = await basehub({ cache: "no-store" }).query({
    spotlight: {
      _title: true,
      title: true,
      description: true,
      link: true,
      image: true,
      hoverImage: true,
    },
  });

  return (
    <div>
      <HeroSection />
      <BoardSection partners={partners.items} spotlight={spotlight} />
      <Footer />
    </div>
  );
}
