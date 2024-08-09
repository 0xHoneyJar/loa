import { Metadata } from "next";
import localFont from "next/font/local";
import "../styles/globals.css";
import "../styles/tailwind.css";
// import "react-grid-layout/css/styles.css";
import MainWrapper from "@/components/main-wrapper";
import Navbar from "@/components/navbar";
import { OpenpanelProvider } from "@openpanel/nextjs";

export const metadata: Metadata = {
  // metadataBase: new URL(""),
  title: "TheHoneyJar",
  description: "THJ is Berachain-native community...",
  openGraph: {
    type: "website",
    title: "",
    description: "",
    images: [
      {
        url: "/metadata_bg.png",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
  },
};

const switzer = localFont({
  src: "../assets/Switzer.ttf",
  variable: "--font-switzer",
});

const clash = localFont({
  src: "../assets/ClashDisplay.ttf",
  variable: "--font-clash",
});

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html className={`${switzer.variable} ${clash.variable}`}>
      <head></head>
      <body>
        <OpenpanelProvider
          clientId="ad8840e6-ded2-4779-81dc-38fbf92d7232"
          trackScreenViews={true}
          trackAttributes={true}
          trackOutgoingLinks={true}
          // If you have a user id, you can pass it here to identify the user
          // profileId={'123'}
        />
        <MainWrapper>
          <Navbar />
          {children}
        </MainWrapper>
      </body>
    </html>
  );
}
