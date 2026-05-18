import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PromoKit Screenshots",
  description: "App Store screenshot generator",
};

const SF = `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Arial, sans-serif`;

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col" style={{ fontFamily: SF }}>
        {children}
      </body>
    </html>
  );
}
