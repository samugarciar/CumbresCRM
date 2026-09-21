'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { Check, Copy, Loader2, Lock, SendHorizontal } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { enviarMensaje } from './acciones';

/**
 * La caja de escribir de la conversación.
 *
 * LA REGLA DE LAS 24 HORAS
 * WhatsApp solo deja mandar texto libre durante 24 horas desde el último
 * mensaje DEL CLIENTE. Pasadas, Meta responde 131047 y **el cliente no
 * recibe nada mientras el asesor cree que sí**. Fuera de la ventana aquí
 * no hay caja: hay una salida hacia las plantillas.
 *
 * El botón apagado es solo la mitad visible. La otra vive en
 * `crm.encolar_envio()`, que revienta si alguien lo intenta igual — un
 * formulario se puede saltar, una función de la base no.
 *
 * EL AVIÓN DESPEGA SOLO CUANDO HAY CANAL
 * Mientras el número siga en Kommo, `canalListo` es false y el botón dice
 * por qué. Encenderlo antes sería un botón que dice "enviado" sobre algo
 * que nadie entregó.
 */
export function CajaDeEscribir({
  contactoId,
  ventanaAbierta,
  cierraAt,
  nuncaEscribio,
  canalListo,
  ahora,
}: {
  contactoId: string;
  ventanaAbierta: boolean;
  cierraAt: string | null;
  nuncaEscribio: boolean;
  canalListo: boolean;
  ahora: string;
}) {
  const [texto, setTexto] = useState('');
  const [copiado, setCopiado] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enviando, iniciar] = useTransition();

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
    }
  };

  const enviar = () => {
    setError(null);
    iniciar(async () => {
      const r = await enviarMensaje(contactoId, texto);
      if (r.ok) {
        // Se vacía solo si salió. Si falló, el texto se queda: volver a
        // escribirlo por un error nuestro es la peor forma de perderlo.
        setTexto('');
      } else {
        setError(r.error ?? 'No se pudo enviar.');
      }
    });
  };

  // ── Fuera de la ventana: no hay caja, hay una salida ──────────────
  // Se quita el campo entero en vez de dejarlo escribible con el botón
  // apagado. Dejar escribir para después no dejar mandar es la forma más
  // segura de que alguien pegue el texto en su WhatsApp personal — y ahí
  // el CRM vuelve a estar ciego.
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
        disabled={enviando}
      />

      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">
          {horas >= 1
            ? `Puedes escribirle libremente ${horas} h más.`
            : 'Te queda menos de una hora de ventana.'}
        </span>

        <div className="flex items-center gap-1.5">
          <Button
            size="sm"
            variant="ghost"
            onClick={copiar}
            disabled={!texto.trim() || enviando}
          >
            {copiado ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
            {copiado ? 'Copiado' : 'Copiar'}
          </Button>

          <Button
            size="sm"
            onClick={enviar}
            disabled={!canalListo || !texto.trim() || enviando}
            title={
              canalListo
                ? 'Enviar por WhatsApp'
                : 'El envío directo llega cuando el número esté en la Cloud API de Meta'
            }
          >
            {enviando ? (
              <Loader2 className="size-3.5 animate-spin" />
            ) : (
              <SendHorizontal className="size-3.5" />
            )}
            {enviando ? 'Enviando' : 'Enviar'}
          </Button>
        </div>
      </div>

      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}

      {!canalListo && (
        <p className="text-xs text-muted-foreground">
          El envío directo todavía no está conectado: por ahora cópialo y pégalo
          en WhatsApp. El botón se enciende solo cuando el canal esté listo.
        </p>
      )}
    </div>
  );
}
