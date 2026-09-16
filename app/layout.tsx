import type { Metadata } from "next";
import { Plus_Jakarta_Sans, Geist_Mono } from "next/font/google";
import "./globals.css";

// Misma tipografía que la plataforma actual, pero cargada por next/font en
// vez de un @import de CSS: el @import bloquea el render hasta que llega la
// hoja de Google Fonts.
const jakarta = Plus_Jakarta_Sans({
  variable: "--font-jakarta",
  subsets: ["latin"],
  // Tres pesos, no seis. El 300 no se puede usar por contraste y el
  // 700/800 emborronan a 13px, que es el cuerpo de las superficies densas
  // de este CRM. Quedarse con 400/500/600 obliga a jerarquizar con tamaño
  // y color en vez de con negrita, que es lo que aguanta la densidad.
  // Además son tres ficheros de fuente menos que descargar.
  weight: ["400", "500", "600"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Cumbres CRM",
  description: "CRM de Cumbres Inmobiliaria",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="es"
      className={`${jakarta.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
