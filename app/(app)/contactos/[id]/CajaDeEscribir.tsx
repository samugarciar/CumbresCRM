'use client';

import { useState } from 'react';
import Link from 'next/link';
import { Check, Copy, Lock, SendHorizontal } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';

/**
 * La caja de escribir de la conversación.
 *
 * Está entera menos el último paso: **falta el canal**. Hasta que el
 * número salga de Kommo y entre en la Cloud API de Meta (fase 5-B), el
 * avión de papel no despega — pero todo lo demás ya funciona, incluida la
 * regla que de verdad importa.
 *
 * LA REGLA DE LAS 24 HORAS, Y POR QUÉ SE VE AQUÍ
 * WhatsApp solo deja mandar texto libre durante 24 horas desde el último
 * mensaje DEL CLIENTE. Pasadas, Meta responde 131047 y **el cliente no
 * recibe nada mientras el asesor cree que sí**. Ese es el fallo que esta
 * caja existe para hacer imposible: fuera de la ventana no se escribe, se
 * elige una plantilla aprobada.
 *
 * El botón apagado es solo la mitad visible. La otra mitad vive en
 * `crm.encolar_envio()`, que revienta si alguien lo intenta igual — un
 * formulario se puede saltar, una función de la base no.
 *
 * Este componente NO recibe todavía el id del contacto, y es a propósito:
 * no lo necesita hasta que haya a quién mandárselo. Un parámetro que solo
 * está ahí para parecer preparado es de lo primero que se queda obsoleto.
 */
export function CajaDeEscribir({
  ventanaAbierta,
  cierraAt,
  nuncaEscribio,
  ahora,
}: {
  ventanaAbierta: boolean;
  cierraAt: string | null;
  nuncaEscribio: boolean;
  ahora: string;
}) {
  const [texto, setTexto] = useState('');
  const [copiado, setCopiado] = useState(false);

  const horas = cierraAt
    ? Math.max(
        0,
        Math.round(
          (new Date(cierraAt).getTime() - new Date(ahora).getTime()) / 3_600_000
        )
      )
    : 0;

  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(texto);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    } catch {
      // Sin permiso de portapapeles el asesor lo selecciona a mano.
      // Avisar de esto sería ruido.
    }
  };

  // ── Fuera de la ventana: no hay caja, hay una salida ──────────────
  // Se quita el campo de texto entero en vez de dejarlo escribible con el
  // botón apagado. Dejar escribir para después no dejar mandar es la
  // forma más segura de que alguien copie el texto y lo pegue en su
  // WhatsApp personal — y ahí el CRM vuelve a estar ciego.
  if (!ventanaAbierta) {
    return (
      <div className="flex flex-col gap-2.5 rounded-lg border border-dashed bg-muted/40 p-4">
        <p className="flex items-start gap-2 text-sm text-warning">
          <Lock className="mt-0.5 size-4 shrink-0" />
          <span>
            {nuncaEscribio ? (
              <>
                <b>Esta persona nunca nos ha escrito</b>, así que WhatsApp no
                permite mandarle texto libre.
              </>
            ) : (
              <>
                <b>Pasaron más de 24 horas</b> desde su último mensaje. El texto
                libre ya no le llega — y WhatsApp no avisa: se pierde en
                silencio.
              </>
            )}
          </span>
        </p>
        <p className="text-sm text-muted-foreground">
          Lo único que sí le llega es una{' '}
          <Link href="/plantillas" className="text-primary hover:underline">
            plantilla aprobada por Meta
          </Link>
          . Están en el panel de la derecha, ya rellenas con sus datos.
        </p>
      </div>
    );
  }

  // ── Dentro de la ventana ──────────────────────────────────────────
  return (
    <div className="flex flex-col gap-2 rounded-lg border bg-card p-3">
      <Textarea
        value={texto}
        onChange={(e) => setTexto(e.target.value)}
        rows={3}
        placeholder="Escríbele…"
        aria-label="Mensaje para esta persona"
      />

      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">
          {horas >= 1
            ? `Puedes escribirle libremente ${horas} h más.`
            : 'Te queda menos de una hora de ventana.'}
        </span>

        <div className="flex items-center gap-1.5">
          <Button size="sm" variant="ghost" onClick={copiar} disabled={!texto.trim()}>
            {copiado ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
            {copiado ? 'Copiado' : 'Copiar'}
          </Button>

          {/* El avión de papel. Apagado hasta que el número esté en Meta:
              encenderlo antes sería un botón que dice "enviado" sobre algo
              que nadie entregó. */}
          <Button
            size="sm"
            disabled
            title="El envío directo llega cuando el número salga de Kommo (fase 5-B)"
            aria-label="Enviar — todavía no disponible"
          >
            <SendHorizontal className="size-3.5" />
            Enviar
          </Button>
        </div>
      </div>

      <p className="text-xs text-muted-foreground">
        El envío directo todavía no está conectado: por ahora cópialo y pégalo
        en WhatsApp. El botón se enciende solo cuando el canal esté listo.
      </p>
    </div>
  );
}
