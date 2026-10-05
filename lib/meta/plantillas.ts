import 'server-only';
import { createClient } from '@/lib/supabase/server';

/**
 * Cliente de integración con Meta Graph API para WhatsApp Business Account (WABA).
 * Gestiona el ciclo de vida de plantillas oficiales HSM (sincronización,
 * envío a revisión, consulta de estado y motivos de rechazo).
 */

const META_API_VERSION = 'v21.0';
const META_BASE_URL = `https://graph.facebook.com/${META_API_VERSION}`;

export interface ComponenteMeta {
  type: 'HEADER' | 'BODY' | 'FOOTER' | 'BUTTONS';
  format?: 'TEXT' | 'IMAGE' | 'DOCUMENT' | 'VIDEO';
  text?: string;
  example?: {
    body_text?: string[][];
    header_text?: string[];
  };
  buttons?: Array<{
    type: 'QUICK_REPLY' | 'URL' | 'PHONE_NUMBER';
    text: string;
    url?: string;
    phone_number?: string;
  }>;
}

export interface PlantillaMetaRemota {
  id: string;
  name: string;
  status: 'APPROVED' | 'PENDING' | 'REJECTED' | 'PAUSED' | 'DISABLED';
  category: 'MARKETING' | 'UTILITY' | 'AUTHENTICATION';
  language: string;
  components: ComponenteMeta[];
  rejected_reason?: string;
  quality_score?: {
    score: 'UNKNOWN' | 'HIGH' | 'MEDIUM' | 'LOW';
  };
}

export interface ResultadoMeta<T = unknown> {
  ok: boolean;
  datos?: T;
  error?: string;
  codigo?: number;
  sinConfigurar?: boolean;
}

/**
 * Obtiene las credenciales activas de Meta para la WABA comercial.
 * Revisa variables de entorno o la línea comercial conectada en crm.lineas.
 */
export async function obtenerCredencialesMeta(): Promise<{
  wabaId: string | null;
  token: string | null;
  fuente: 'env' | 'lineas' | null;
}> {
  // 1. Si están definidas en el entorno
  if (process.env.META_WABA_ID && (process.env.META_ACCESS_TOKEN || process.env.WHATSAPP_TOKEN)) {
    return {
      wabaId: process.env.META_WABA_ID,
      token: process.env.META_ACCESS_TOKEN || process.env.WHATSAPP_TOKEN || null,
      fuente: 'env',
    };
  }

  // 2. Consulta en crm.lineas
  try {
    const supabase = await createClient();
    const { data: linea } = await supabase
      .schema('crm')
      .from('lineas')
      .select('waba_id, wa_phone_number_id')
      .eq('embudo', 'comercial')
      .eq('activa', true)
      .maybeSingle();

    if (linea?.waba_id) {
      // Si la línea tiene token en Vault
      const token = process.env.WHATSAPP_TOKEN || process.env.META_ACCESS_TOKEN || null;
      return {
        wabaId: linea.waba_id,
        token,
        fuente: 'lineas',
      };
    }
  } catch {
    // Si no se puede consultar la BD, cae a no configurado
  }

  return { wabaId: null, token: null, fuente: null };
}

/**
 * Normaliza el estado de Meta a nuestro modelo del CRM:
 * APPROVED → aprobada
 * PENDING → enviada
 * REJECTED → rechazada
 * PAUSED / DISABLED → rechazada
 */
export function normalizarEstadoMeta(
  status: string
): 'aprobada' | 'enviada' | 'rechazada' | 'borrador' {
  switch (status.toUpperCase()) {
    case 'APPROVED':
      return 'aprobada';
    case 'PENDING':
      return 'enviada';
    case 'REJECTED':
    case 'PAUSED':
    case 'DISABLED':
      return 'rechazada';
    default:
      return 'borrador';
  }
}

/**
 * Sincroniza las plantillas de la WABA de Meta hacia crm.plantillas.
 * Descarga las plantillas existentes, actualiza estados (APPROVED, REJECTED)
 * y almacena el motivo de rechazo si aplica.
 */
export async function sincronizarPlantillasWABA(
  inmobiliariaId: string
): Promise<ResultadoMeta<{ total: number; agregadas: number; actualizadas: number }>> {
  const { wabaId, token } = await obtenerCredencialesMeta();

  if (!wabaId || !token) {
    return {
      ok: false,
      sinConfigurar: true,
      error:
        'No se encontraron credenciales de Meta configuradas (WABA ID y Token de acceso). Configúralas en las líneas o en las variables de entorno.',
    };
  }

  try {
    const url = `${META_BASE_URL}/${wabaId}/message_templates?fields=id,name,status,category,language,components,rejected_reason,quality_score&limit=100`;
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      next: { revalidate: 0 },
    });

    const respuesta = await res.json();

    if (!res.ok) {
      const mensaje = respuesta?.error?.message ?? `Error ${res.status} al consultar Meta`;
      return {
        ok: false,
        error: `Meta rechazó la consulta: ${mensaje}`,
        codigo: respuesta?.error?.code,
      };
    }

    const remotas = (respuesta.data ?? []) as PlantillaMetaRemota[];
    const supabase = await createClient();
    const crm = supabase.schema('crm');

    let agregadas = 0;
    let actualizadas = 0;

    for (const remota of remotas) {
      // Extrae el texto del componente BODY
      const bodyComp = remota.components?.find((c) => c.type === 'BODY');
      const cuerpoTexto = bodyComp?.text || '';
      if (!cuerpoTexto) continue;

      const estadoCRM = normalizarEstadoMeta(remota.status);
      const categoriaCRM =
        remota.category.toLowerCase() === 'marketing' ? 'marketing' : 'utilidad';

      // Busca si ya existe en crm.plantillas
      const { data: existente } = await crm
        .from('plantillas')
        .select('id, estado_meta, motivo_rechazo_meta')
        .eq('inmobiliaria_id', inmobiliariaId)
        .eq('nombre_meta', remota.name)
        .maybeSingle();

      if (existente) {
        // Actualiza estado y motivo si cambiaron
        await crm
          .from('plantillas')
          .update({
            estado_meta: estadoCRM,
            motivo_rechazo_meta: remota.rejected_reason || null,
            categoria: categoriaCRM,
            idioma: remota.language || 'es',
            updated_at: new Date().toISOString(),
          })
          .eq('id', existente.id);
        actualizadas++;
      } else {
        // Registra la plantilla importada desde Meta
        const nombreHumano = remota.name
          .replace(/_/g, ' ')
          .replace(/\b\w/g, (l) => l.toUpperCase());

        await crm.from('plantillas').insert({
          inmobiliaria_id: inmobiliariaId,
          nombre: nombreHumano,
          cuerpo: cuerpoTexto,
          categoria: categoriaCRM,
          tipo: 'whatsapp',
          estado_meta: estadoCRM,
          nombre_meta: remota.name,
          idioma: remota.language || 'es',
          motivo_rechazo_meta: remota.rejected_reason || null,
        });
        agregadas++;
      }
    }

    return {
      ok: true,
      datos: {
        total: remotas.length,
        agregadas,
        actualizadas,
      },
    };
  } catch (err) {
    return {
      ok: false,
      error:
        err instanceof Error
          ? `Error de conexión con Meta: ${err.message}`
          : 'Error desconocido al conectar con Meta',
    };
  }
}

/**
 * Envía una plantilla oficial de WhatsApp a revisión de Meta.
 * Construye el payload conforme a la especificación de Meta Graph API.
 */
export async function enviarPlantillaRevisionMeta(opciones: {
  nombreMeta: string;
  cuerpo: string;
  categoria: 'utilidad' | 'marketing';
  idioma?: string;
  ejemplos?: string[];
}): Promise<ResultadoMeta<{ idMeta: string; status: string }>> {
  const { wabaId, token } = await obtenerCredencialesMeta();

  if (!wabaId || !token) {
    return {
      ok: false,
      sinConfigurar: true,
      error:
        'No se encontraron credenciales de Meta configuradas para enviar a revisión.',
    };
  }

  // Prepara los ejemplos para el body si hay variables {{nombre}}, etc.
  const variablesEncontradas = opciones.cuerpo.match(/\{\{\s*([a-z_]+)\s*\}\}/g) ?? [];
  const ejemplosBody =
    variablesEncontradas.length > 0
      ? [
          variablesEncontradas.map((v, i) => {
            if (opciones.ejemplos && opciones.ejemplos[i]) return opciones.ejemplos[i];
            if (v.includes('nombre')) return 'Juan Pérez';
            if (v.includes('asesor')) return 'Alejandro Rojas';
            if (v.includes('inmueble')) return 'Apto Poblado 401';
            if (v.includes('precio')) return '$2.500.000';
            return 'Ejemplo';
          }),
        ]
      : undefined;

  const componentes: ComponenteMeta[] = [
    {
      type: 'BODY',
      text: opciones.cuerpo,
      example: ejemplosBody ? { body_text: ejemplosBody } : undefined,
    },
  ];

  const payload = {
    name: opciones.nombreMeta.toLowerCase().trim(),
    category: opciones.categoria.toUpperCase(),
    language: opciones.idioma || 'es',
    components: componentes,
    parameter_format: 'NAMED',
  };

  try {
    const url = `${META_BASE_URL}/${wabaId}/message_templates`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const respuesta = await res.json();

    if (!res.ok) {
      const errorMeta = respuesta?.error?.message ?? `Error HTTP ${res.status}`;
      return {
        ok: false,
        error: `Meta no aceptó la plantilla: ${errorMeta}`,
        codigo: respuesta?.error?.code,
      };
    }

    return {
      ok: true,
      datos: {
        idMeta: respuesta.id,
        status: respuesta.status ?? 'PENDING',
      },
    };
  } catch (err) {
    return {
      ok: false,
      error:
        err instanceof Error
          ? `Error de red al enviar a Meta: ${err.message}`
          : 'Error desconocido al enviar a Meta',
    };
  }
}
