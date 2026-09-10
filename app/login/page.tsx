import { Suspense } from 'react';
import { FormularioLogin } from './FormularioLogin';

// El formulario usa useSearchParams() para leer `siguiente`, y eso obliga a
// un límite de Suspense: sin él, Next no puede prerenderizar esta ruta.
// Ver https://nextjs.org/docs/messages/missing-suspense-with-csr-bailout
export default function PaginaLogin() {
  return (
    <Suspense>
      <FormularioLogin />
    </Suspense>
  );
}
