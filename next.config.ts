import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Hay un package-lock.json suelto en el directorio del usuario, fuera
  // del repo, y Turbopack lo toma como candidato a raíz del proyecto.
  // Fijarla evita el aviso y hace que el build no dependa de qué haya
  // por encima de esta carpeta.
  turbopack: {
    root: __dirname,
  },

  // No anunciar con qué está hecho: a nadie de fuera le sirve saberlo.
  poweredByHeader: false,

  // Un CRM con datos de clientes no se mete en un iframe ajeno ni sale en
  // un buscador. Ver node_modules/next/dist/docs/01-app/03-api-reference/
  // 05-config/01-next-config-js/headers.md
  headers() {
    return [
      {
        source: '/:path*',
        headers: [
          // Nadie puede incrustar el CRM en su página para engañar a un
          // asesor y que pulse lo que no ve (clickjacking).
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          // Al salir hacia otro sitio, no se lleva la ruta: las rutas del
          // CRM llevan ids de contactos.
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'X-Robots-Tag', value: 'noindex, nofollow' },
        ],
      },
    ];
  },
};

export default nextConfig;
