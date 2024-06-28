import { Metadata } from "next";
import "../styles/globals.css";
import "../styles/tailwind.css";
import localFont from "next/font/local";
import "react-grid-layout/css/styles.css";
import Navbar from "@/components/navbar";

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

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html className={`${switzer.variable}`}>
      <head></head>
      <body>
        <div className="mx-auto min-w-[24rem] max-w-[112rem] relative overflow-hidden">
          <Navbar />
          {children}
        </div>
      </body>
    </html>
  );
}
