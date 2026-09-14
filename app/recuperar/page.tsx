import { Suspense } from 'react';
import { FormularioRecuperar } from './FormularioRecuperar';

// El formulario lee `caducado` con useSearchParams(), y eso obliga a un
// límite de Suspense: sin él Next no puede prerenderizar esta ruta.
// Mismo patrón que /login.
export default function PaginaRecuperar() {
  return (
    <Suspense>
      <FormularioRecuperar />
    </Suspense>
  );
}
