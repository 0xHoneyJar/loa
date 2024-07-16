import { Metadata } from "next";
import "../styles/globals.css";
import "../styles/tailwind.css";
import localFont from "next/font/local";
// import "react-grid-layout/css/styles.css";
import Navbar from "@/components/navbar";
import MainWrapper from "@/components/main-wrapper";

export const metadata: Metadata = {
  // metadataBase: new URL(""),
  title: "",
  description: "",
  openGraph: {
    type: "website",
    title: "",
    description: "",
    images: [
      {
        url: "https://res.cloudinary.com/honeyjar/image/upload/v1677023883/THJ_WebBanner.jpg",
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
        <MainWrapper>
          <Navbar />
          {children}
        </MainWrapper>
      </body>
    </html>
  );
}
