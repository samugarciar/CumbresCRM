import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Hay un package-lock.json suelto en el directorio del usuario, fuera
  // del repo, y Turbopack lo toma como candidato a raíz del proyecto.
  // Fijarla evita el aviso y hace que el build no dependa de qué haya
  // por encima de esta carpeta.
  turbopack: {
    root: __dirname,
  },
};

export default nextConfig;
