/* eslint-disable @next/next/no-head-element */

import { Web3Provider } from "@/components/web3-provider";
import { Metadata } from "next";
import "../styles/globals.css";
import "../styles/tailwind.css";
import localFont from "next/font/local";
import "react-grid-layout/css/styles.css";
import Navbar from "@/app/Navbar";
// import "react-resizable/css/styles.css";

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
        {/* <Web3Provider> */}
        <div className="mx-auto min-w-[24rem] max-w-[112rem] relative overflow-hidden">
          <>
            <Navbar />
            {children}
          </>
        </div>
        {/* </Web3Provider> */}
      </body>
    </html>
  );
}
