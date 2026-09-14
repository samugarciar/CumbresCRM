export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  crm: {
    Tables: {
      actividades: {
        Row: {
          cita_id: string | null
          contacto_id: string | null
          creado_por: string | null
          created_at: string
          cuerpo: string | null
          id: number
          inmobiliaria_id: string
          inmueble_id: string | null
          metadata: Json
          ocurrido_at: string
          origen: string
          tipo: string
        }
        Insert: {
          cita_id?: string | null
          contacto_id?: string | null
          creado_por?: string | null
          created_at?: string
          cuerpo?: string | null
          id?: never
          inmobiliaria_id: string
          inmueble_id?: string | null
          metadata?: Json
          ocurrido_at?: string
          origen?: string
          tipo: string
        }
        Update: {
          cita_id?: string | null
          contacto_id?: string | null
          creado_por?: string | null
          created_at?: string
          cuerpo?: string | null
          id?: never
          inmobiliaria_id?: string
          inmueble_id?: string | null
          metadata?: Json
          ocurrido_at?: string
          origen?: string
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "actividades_cita_id_fkey"
            columns: ["cita_id"]
            isOneToOne: false
            referencedRelation: "v_citas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actividades_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actividades_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actividades_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "v_inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos: {
        Row: {
          asesor_id: string | null
          consentimiento: boolean
          consentimiento_at: string | null
          consentimiento_canal: string | null
          created_at: string
          deleted_at: string | null
          email: string | null
          external_ids: Json
          id: string
          inmobiliaria_id: string
          merged_into_id: string | null
          nombre: string | null
          notas: string | null
          origen: string | null
          telefono_crudo: string | null
          telefono_e164: string | null
          tipo: string
          ultima_actividad_at: string | null
          updated_at: string
          utm: Json
        }
        Insert: {
          asesor_id?: string | null
          consentimiento?: boolean
          consentimiento_at?: string | null
          consentimiento_canal?: string | null
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          external_ids?: Json
          id?: string
          inmobiliaria_id: string
          merged_into_id?: string | null
          nombre?: string | null
          notas?: string | null
          origen?: string | null
          telefono_crudo?: string | null
          telefono_e164?: string | null
          tipo?: string
          ultima_actividad_at?: string | null
          updated_at?: string
          utm?: Json
        }
        Update: {
          asesor_id?: string | null
          consentimiento?: boolean
          consentimiento_at?: string | null
          consentimiento_canal?: string | null
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          external_ids?: Json
          id?: string
          inmobiliaria_id?: string
          merged_into_id?: string | null
          nombre?: string | null
          notas?: string | null
          origen?: string | null
          telefono_crudo?: string | null
          telefono_e164?: string | null
          tipo?: string
          ultima_actividad_at?: string | null
          updated_at?: string
          utm?: Json
        }
        Relationships: [
          {
            foreignKeyName: "contactos_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_merged_into_id_fkey"
            columns: ["merged_into_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
        ]
      }
      etapas: {
        Row: {
          automatica: boolean
          codigo: string
          dias_pudricion: number | null
          etiqueta: string
          orden: number
        }
        Insert: {
          automatica?: boolean
          codigo: string
          dias_pudricion?: number | null
          etiqueta: string
          orden: number
        }
        Update: {
          automatica?: boolean
          codigo?: string
          dias_pudricion?: number | null
          etiqueta?: string
          orden?: number
        }
        Relationships: []
      }
      eventos: {
        Row: {
          created_at: string
          error: string | null
          estado: string
          fila_origen_id: string
          id: number
          inmobiliaria_id: string | null
          intentos: number
          payload: Json
          procesado_at: string | null
          tabla_origen: string
          tipo: string
        }
        Insert: {
          created_at?: string
          error?: string | null
          estado?: string
          fila_origen_id: string
          id?: never
          inmobiliaria_id?: string | null
          intentos?: number
          payload?: Json
          procesado_at?: string | null
          tabla_origen: string
          tipo: string
        }
        Update: {
          created_at?: string
          error?: string | null
          estado?: string
          fila_origen_id?: string
          id?: never
          inmobiliaria_id?: string | null
          intentos?: number
          payload?: Json
          procesado_at?: string | null
          tabla_origen?: string
          tipo?: string
        }
        Relationships: []
      }
      identidades: {
        Row: {
          contacto_id: string
          created_at: string
          id: number
          inmobiliaria_id: string
          origen: string | null
          tipo: string
          valor: string
        }
        Insert: {
          contacto_id: string
          created_at?: string
          id?: never
          inmobiliaria_id: string
          origen?: string | null
          tipo: string
          valor: string
        }
        Update: {
          contacto_id?: string
          created_at?: string
          id?: never
          inmobiliaria_id?: string
          origen?: string | null
          tipo?: string
          valor?: string
        }
        Relationships: [
          {
            foreignKeyName: "identidades_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
        ]
      }
      lecturas: {
        Row: {
          contacto_id: string
          inmobiliaria_id: string
          usuario_id: string
          visto_hasta: string
        }
        Insert: {
          contacto_id: string
          inmobiliaria_id: string
          usuario_id: string
          visto_hasta?: string
        }
        Update: {
          contacto_id?: string
          inmobiliaria_id?: string
          usuario_id?: string
          visto_hasta?: string
        }
        Relationships: [
          {
            foreignKeyName: "lecturas_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lecturas_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
        ]
      }
      oportunidades: {
        Row: {
          asesor_id: string | null
          cerrada_at: string | null
          cerrada_por: string | null
          contacto_id: string
          created_at: string
          escalado_at: string | null
          estado: string
          etapa: string
          etapa_at: string
          id: string
          inmobiliaria_id: string
          inmueble_id: string | null
          motivo_perdida: string | null
          updated_at: string
          zona: string | null
        }
        Insert: {
          asesor_id?: string | null
          cerrada_at?: string | null
          cerrada_por?: string | null
          contacto_id: string
          created_at?: string
          escalado_at?: string | null
          estado?: string
          etapa?: string
          etapa_at?: string
          id?: string
          inmobiliaria_id: string
          inmueble_id?: string | null
          motivo_perdida?: string | null
          updated_at?: string
          zona?: string | null
        }
        Update: {
          asesor_id?: string | null
          cerrada_at?: string | null
          cerrada_por?: string | null
          contacto_id?: string
          created_at?: string
          escalado_at?: string | null
          estado?: string
          etapa?: string
          etapa_at?: string
          id?: string
          inmobiliaria_id?: string
          inmueble_id?: string | null
          motivo_perdida?: string | null
          updated_at?: string
          zona?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "oportunidades_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "oportunidades_cerrada_por_fkey"
            columns: ["cerrada_por"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "oportunidades_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "oportunidades_etapa_fkey"
            columns: ["etapa"]
            isOneToOne: false
            referencedRelation: "etapas"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "oportunidades_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "v_inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      requerimientos: {
        Row: {
          activo: boolean
          barrios: string[] | null
          ciudad: string | null
          contacto_id: string
          created_at: string
          habitaciones_min: number | null
          id: string
          inmobiliaria_id: string
          notas: string | null
          origen: string
          precio_max: number | null
          tipo_inmueble: string[] | null
          tipo_transaccion: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          barrios?: string[] | null
          ciudad?: string | null
          contacto_id: string
          created_at?: string
          habitaciones_min?: number | null
          id?: string
          inmobiliaria_id: string
          notas?: string | null
          origen?: string
          precio_max?: number | null
          tipo_inmueble?: string[] | null
          tipo_transaccion?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          barrios?: string[] | null
          ciudad?: string | null
          contacto_id?: string
          created_at?: string
          habitaciones_min?: number | null
          id?: string
          inmobiliaria_id?: string
          notas?: string | null
          origen?: string
          precio_max?: number | null
          tipo_inmueble?: string[] | null
          tipo_transaccion?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "requerimientos_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
        ]
      }
      transiciones: {
        Row: {
          estado_hasta: string | null
          etapa_desde: string | null
          etapa_hasta: string | null
          id: number
          inmobiliaria_id: string
          motivo: string | null
          ocurrido_at: string
          oportunidad_id: string
          origen: string
          usuario_id: string | null
        }
        Insert: {
          estado_hasta?: string | null
          etapa_desde?: string | null
          etapa_hasta?: string | null
          id?: never
          inmobiliaria_id: string
          motivo?: string | null
          ocurrido_at?: string
          oportunidad_id: string
          origen?: string
          usuario_id?: string | null
        }
        Update: {
          estado_hasta?: string | null
          etapa_desde?: string | null
          etapa_hasta?: string | null
          id?: never
          inmobiliaria_id?: string
          motivo?: string | null
          ocurrido_at?: string
          oportunidad_id?: string
          origen?: string
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transiciones_etapa_desde_fkey"
            columns: ["etapa_desde"]
            isOneToOne: false
            referencedRelation: "etapas"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "transiciones_etapa_hasta_fkey"
            columns: ["etapa_hasta"]
            isOneToOne: false
            referencedRelation: "etapas"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "transiciones_oportunidad_id_fkey"
            columns: ["oportunidad_id"]
            isOneToOne: false
            referencedRelation: "oportunidades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transiciones_oportunidad_id_fkey"
            columns: ["oportunidad_id"]
            isOneToOne: false
            referencedRelation: "v_oportunidades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transiciones_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      v_asesores: {
        Row: {
          email: string | null
          id: string | null
          inmobiliaria_id: string | null
          nombre_completo: string | null
          rol: string | null
          telefono: string | null
        }
        Insert: {
          email?: string | null
          id?: string | null
          inmobiliaria_id?: string | null
          nombre_completo?: string | null
          rol?: string | null
          telefono?: string | null
        }
        Update: {
          email?: string | null
          id?: string | null
          inmobiliaria_id?: string | null
          nombre_completo?: string | null
          rol?: string | null
          telefono?: string | null
        }
        Relationships: []
      }
      v_citas: {
        Row: {
          alcance: string | null
          cliente_email: string | null
          cliente_nombre: string | null
          cliente_telefono: string | null
          confirmada_at: string | null
          created_at: string | null
          estado: string | null
          fecha: string | null
          hora_fin: string | null
          hora_inicio: string | null
          id: string | null
          inmobiliaria_id: string | null
          inmueble_id: string | null
          origen: string | null
          telefono_e164: string | null
          unidad: string | null
        }
        Insert: {
          alcance?: string | null
          cliente_email?: string | null
          cliente_nombre?: string | null
          cliente_telefono?: string | null
          confirmada_at?: string | null
          created_at?: string | null
          estado?: string | null
          fecha?: string | null
          hora_fin?: string | null
          hora_inicio?: string | null
          id?: string | null
          inmobiliaria_id?: string | null
          inmueble_id?: string | null
          origen?: string | null
          telefono_e164?: never
          unidad?: string | null
        }
        Update: {
          alcance?: string | null
          cliente_email?: string | null
          cliente_nombre?: string | null
          cliente_telefono?: string | null
          confirmada_at?: string | null
          created_at?: string | null
          estado?: string | null
          fecha?: string | null
          hora_fin?: string | null
          hora_inicio?: string | null
          id?: string | null
          inmobiliaria_id?: string | null
          inmueble_id?: string | null
          origen?: string | null
          telefono_e164?: never
          unidad?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "citas_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "v_inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      v_inmuebles: {
        Row: {
          arrendasoft_id: number | null
          asesor_id: string | null
          banos: number | null
          barrio: string | null
          ciudad: string | null
          created_at: string | null
          direccion: string | null
          estado: string | null
          habitaciones: number | null
          id: string | null
          imagenes: Json | null
          inmobiliaria_id: string | null
          precio: number | null
          tipo_inmueble: string | null
          tipo_transaccion: string | null
          titulo: string | null
          unidad: string | null
        }
        Insert: {
          arrendasoft_id?: number | null
          asesor_id?: never
          banos?: number | null
          barrio?: string | null
          ciudad?: string | null
          created_at?: string | null
          direccion?: string | null
          estado?: string | null
          habitaciones?: number | null
          id?: string | null
          imagenes?: Json | null
          inmobiliaria_id?: string | null
          precio?: number | null
          tipo_inmueble?: string | null
          tipo_transaccion?: string | null
          titulo?: string | null
          unidad?: string | null
        }
        Update: {
          arrendasoft_id?: number | null
          asesor_id?: never
          banos?: number | null
          barrio?: string | null
          ciudad?: string | null
          created_at?: string | null
          direccion?: string | null
          estado?: string | null
          habitaciones?: number | null
          id?: string | null
          imagenes?: Json | null
          inmobiliaria_id?: string | null
          precio?: number | null
          tipo_inmueble?: string | null
          tipo_transaccion?: string | null
          titulo?: string | null
          unidad?: string | null
        }
        Relationships: []
      }
      v_oportunidades: {
        Row: {
          asesor_id: string | null
          cerrada_at: string | null
          contacto_id: string | null
          created_at: string | null
          escalado_at: string | null
          estado: string | null
          estancada: boolean | null
          etapa: string | null
          etapa_at: string | null
          etapa_etiqueta: string | null
          etapa_orden: number | null
          id: string | null
          inmobiliaria_id: string | null
          inmueble_id: string | null
          motivo_perdida: string | null
          nombre: string | null
          telefono_e164: string | null
          ultima_actividad_at: string | null
          visita_realizada_origen: string | null
          zona: string | null
        }
        Relationships: [
          {
            foreignKeyName: "oportunidades_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "v_asesores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "oportunidades_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "oportunidades_etapa_fkey"
            columns: ["etapa"]
            isOneToOne: false
            referencedRelation: "etapas"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "oportunidades_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "v_inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      v_timeline: {
        Row: {
          contacto_id: string | null
          cuerpo: string | null
          id: number | null
          inmobiliaria_id: string | null
          inmueble_barrio: string | null
          inmueble_id: string | null
          inmueble_titulo: string | null
          metadata: Json | null
          ocurrido_at: string | null
          origen: string | null
          tipo: string | null
        }
        Relationships: [
          {
            foreignKeyName: "actividades_contacto_id_fkey"
            columns: ["contacto_id"]
            isOneToOne: false
            referencedRelation: "contactos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actividades_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "v_inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      abrir_oportunidad: { Args: { p_contacto_id: string }; Returns: string }
      backfill: { Args: { p_inmobiliaria_id: string }; Returns: Json }
      backfill_pipeline: {
        Args: never
        Returns: {
          con_zona: number
          escaladas: number
          oportunidades_creadas: number
        }[]
      }
      backfill_requerimientos: {
        Args: never
        Returns: {
          actualizados: number
          creados: number
          personas: number
        }[]
      }
      bandeja_contactos: {
        Args: {
          p_cursor_at?: string
          p_cursor_id?: string
          p_limite?: number
          p_sin_telefono?: boolean
          p_texto?: string
          p_tipo?: string
        }
        Returns: {
          asesor_id: string
          id: string
          n_actividades: number
          nombre: string
          orden_at: string
          origen: string
          sin_leer: number
          telefono_crudo: string
          telefono_e164: string
          tipo: string
          ultima_actividad_at: string
        }[]
      }
      calidad_nombre: { Args: { p_nombre: string }; Returns: number }
      cerrar_fantasmas: { Args: { p_dias?: number }; Returns: number }
      cerrar_oportunidad: {
        Args: {
          p_estado: string
          p_inmueble_id?: string
          p_motivo_perdida?: string
          p_nota?: string
          p_oportunidad_id: string
        }
        Returns: undefined
      }
      clientes_para: {
        Args: { p_inmueble_id: string; p_minimo?: number }
        Returns: {
          contacto_id: string
          especificidad: number
          estado: string
          etapa: string
          nombre: string
          oportunidad_id: string
          pidio: string
          puntaje: number
          requerimiento_id: string
          telefono_e164: string
          ultima_actividad_at: string
        }[]
      }
      coincidencias: {
        Args: {
          p_inmueble_id?: string
          p_limite?: number
          p_minimo?: number
          p_por_inmueble?: number
        }
        Returns: {
          barrio: string
          ciudad: string
          contacto_id: string
          especificidad: number
          etapa: string
          habitaciones: number
          inmueble_desde: string
          inmueble_id: string
          nombre: string
          oportunidad_id: string
          pidio: string
          precio: number
          puntaje: number
          requerimiento_id: string
          telefono_e164: string
          tipo_inmueble: string
          tipo_transaccion: string
          titulo: string
          total_clientes: number
          ultima_actividad_at: string
        }[]
      }
      especificidad: { Args: { p_requerimiento_id: string }; Returns: number }
      identidades_de_conversacion: {
        Args: {
          p_kommo_contact: string
          p_kommo_lead: string
          p_telefono: string
        }
        Returns: Json
      }
      igual_zona: { Args: { a: string; b: string }; Returns: boolean }
      inmuebles_para: {
        Args: { p_contacto_id: string; p_limite?: number; p_minimo?: number }
        Returns: {
          barrio: string
          ciudad: string
          habitaciones: number
          inmueble_id: string
          precio: number
          puntaje: number
          tipo_inmueble: string
          titulo: string
        }[]
      }
      marcar_leido: { Args: { p_contacto_id: string }; Returns: undefined }
      mejor_nombre: {
        Args: { p_actual: string; p_candidato: string }
        Returns: string
      }
      mover_etapa: {
        Args: { p_etapa: string; p_motivo?: string; p_oportunidad_id: string }
        Returns: undefined
      }
      normaliza_zonas: { Args: { p: string[] }; Returns: string[] }
      normalizar_telefono: { Args: { p_tel: string }; Returns: string }
      orden_por_evidencia: { Args: { p_contacto_id: string }; Returns: number }
      puntaje: {
        Args: {
          i_barrio: string
          i_ciudad: string
          i_estado: string
          i_hab: number
          i_precio: number
          i_tipo: string
          i_transaccion: string
          r_barrios: string[]
          r_ciudad: string
          r_hab_min: number
          r_precio_max: number
          r_tipos: string[]
          r_transaccion: string
        }
        Returns: number
      }
      puntaje_match: {
        Args: { p_inmueble_id: string; p_requerimiento_id: string }
        Returns: number
      }
      reabrir_oportunidad: {
        Args: { p_oportunidad_id: string }
        Returns: undefined
      }
      recalcular_oportunidad: {
        Args: { p_contacto_id: string }
        Returns: boolean
      }
      recalcular_pipeline: { Args: never; Returns: number }
      recuperar_telefonos_desde_herramientas: {
        Args: { p_inmobiliaria_id: string }
        Returns: Json
      }
      registrar_fallo: {
        Args: {
          p_error: string
          p_fila: string
          p_inmobiliaria: string
          p_payload: Json
          p_tabla: string
          p_tipo: string
        }
        Returns: undefined
      }
      reintentar_eventos: { Args: { p_limite?: number }; Returns: Json }
      resolver_contacto: {
        Args: {
          p_identidades: Json
          p_inmobiliaria_id: string
          p_nombre?: string
          p_origen?: string
          p_telefono_crudo?: string
          p_tipo_contacto?: string
        }
        Returns: string
      }
      resumen_contacto: {
        Args: { p_contacto_id: string }
        Returns: {
          actividades_total: number
          esperando_segundos: number
          inmuebles: string[]
          mensajes_bot: number
          mensajes_cliente: number
          sin_leer: number
          solicitudes_horario: number
          ultimo_del_cliente_at: string
          visitas_agendadas: number
          visitas_canceladas: number
          visitas_realizadas: number
          visto_hasta: string
        }[]
      }
      sincronizar_escalamientos: { Args: never; Returns: number }
      tablero: {
        Args: {
          p_asesor?: string
          p_limite?: number
          p_solo_pendiente?: boolean
          p_texto?: string
          p_zona?: string
        }
        Returns: {
          contacto_id: string
          escalado_at: string
          escalado_atendido: boolean
          escalado_sin_atender: boolean
          estancada: boolean
          etapa: string
          etapa_at: string
          etapa_orden: number
          id: string
          nombre: string
          telefono_e164: string
          total_en_etapa: number
          ultima_actividad_at: string
          visita_realizada_origen: string
          zona: string
        }[]
      }
      zonas: {
        Args: never
        Returns: {
          oportunidades: number
          zona: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      agente_comercial_conversaciones: {
        Row: {
          cliente_nombre: string | null
          created_at: string
          id: string
          inmobiliaria_id: string
          kommo_contact_id: string | null
          kommo_lead_id: string | null
          telefono: string
          updated_at: string
        }
        Insert: {
          cliente_nombre?: string | null
          created_at?: string
          id?: string
          inmobiliaria_id: string
          kommo_contact_id?: string | null
          kommo_lead_id?: string | null
          telefono: string
          updated_at?: string
        }
        Update: {
          cliente_nombre?: string | null
          created_at?: string
          id?: string
          inmobiliaria_id?: string
          kommo_contact_id?: string | null
          kommo_lead_id?: string | null
          telefono?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agente_comercial_conversaciones_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
        ]
      }
      agente_comercial_mensajes: {
        Row: {
          contenido: string
          conversacion_id: string
          created_at: string
          herramientas_usadas: Json | null
          id: string
          rol: string
        }
        Insert: {
          contenido: string
          conversacion_id: string
          created_at?: string
          herramientas_usadas?: Json | null
          id?: string
          rol: string
        }
        Update: {
          contenido?: string
          conversacion_id?: string
          created_at?: string
          herramientas_usadas?: Json | null
          id?: string
          rol?: string
        }
        Relationships: [
          {
            foreignKeyName: "agente_comercial_mensajes_conversacion_id_fkey"
            columns: ["conversacion_id"]
            isOneToOne: false
            referencedRelation: "agente_comercial_conversaciones"
            referencedColumns: ["id"]
          },
        ]
      }
      agente_comercial_uso: {
        Row: {
          conversacion_id: string | null
          costo_usd: number
          created_at: string
          escalado: boolean
          etapa: string | null
          id: string
          inmobiliaria_id: string
          modelo: string
          tokens_cache: number
          tokens_entrada: number
          tokens_salida: number
        }
        Insert: {
          conversacion_id?: string | null
          costo_usd?: number
          created_at?: string
          escalado?: boolean
          etapa?: string | null
          id?: string
          inmobiliaria_id: string
          modelo: string
          tokens_cache?: number
          tokens_entrada?: number
          tokens_salida?: number
        }
        Update: {
          conversacion_id?: string | null
          costo_usd?: number
          created_at?: string
          escalado?: boolean
          etapa?: string | null
          id?: string
          inmobiliaria_id?: string
          modelo?: string
          tokens_cache?: number
          tokens_entrada?: number
          tokens_salida?: number
        }
        Relationships: [
          {
            foreignKeyName: "agente_comercial_uso_conversacion_id_fkey"
            columns: ["conversacion_id"]
            isOneToOne: false
            referencedRelation: "agente_comercial_conversaciones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agente_comercial_uso_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
        ]
      }
      agentes_config: {
        Row: {
          activo: boolean
          agente: string
          id: string
          inmobiliaria_id: string
          limite_mensual_usd: number | null
          prompt_sistema: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          activo?: boolean
          agente: string
          id?: string
          inmobiliaria_id: string
          limite_mensual_usd?: number | null
          prompt_sistema?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          activo?: boolean
          agente?: string
          id?: string
          inmobiliaria_id?: string
          limite_mensual_usd?: number | null
          prompt_sistema?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agentes_config_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agentes_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      bi_artefactos: {
        Row: {
          contenido_markdown: string
          conversacion_id: string | null
          created_at: string
          id: string
          inmobiliaria_id: string
          resumen: string | null
          tipo: string
          titulo: string
          usuario_id: string | null
        }
        Insert: {
          contenido_markdown: string
          conversacion_id?: string | null
          created_at?: string
          id?: string
          inmobiliaria_id: string
          resumen?: string | null
          tipo?: string
          titulo: string
          usuario_id?: string | null
        }
        Update: {
          contenido_markdown?: string
          conversacion_id?: string | null
          created_at?: string
          id?: string
          inmobiliaria_id?: string
          resumen?: string | null
          tipo?: string
          titulo?: string
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bi_artefactos_conversacion_id_fkey"
            columns: ["conversacion_id"]
            isOneToOne: false
            referencedRelation: "bi_conversaciones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bi_artefactos_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bi_artefactos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      bi_conversaciones: {
        Row: {
          created_at: string
          id: string
          inmobiliaria_id: string
          titulo: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          inmobiliaria_id: string
          titulo: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          inmobiliaria_id?: string
          titulo?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bi_conversaciones_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bi_conversaciones_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      bi_mensajes: {
        Row: {
          contenido: Json
          conversacion_id: string
          created_at: string
          id: string
          rol: string
        }
        Insert: {
          contenido: Json
          conversacion_id: string
          created_at?: string
          id?: string
          rol: string
        }
        Update: {
          contenido?: Json
          conversacion_id?: string
          created_at?: string
          id?: string
          rol?: string
        }
        Relationships: [
          {
            foreignKeyName: "bi_mensajes_conversacion_id_fkey"
            columns: ["conversacion_id"]
            isOneToOne: false
            referencedRelation: "bi_conversaciones"
            referencedColumns: ["id"]
          },
        ]
      }
      bi_uso: {
        Row: {
          conversacion_id: string | null
          costo_usd: number
          created_at: string
          id: string
          inmobiliaria_id: string
          modelo: string
          tokens_cache_escritura: number
          tokens_cache_lectura: number
          tokens_entrada: number
          tokens_salida: number
          usuario_id: string | null
        }
        Insert: {
          conversacion_id?: string | null
          costo_usd?: number
          created_at?: string
          id?: string
          inmobiliaria_id: string
          modelo: string
          tokens_cache_escritura?: number
          tokens_cache_lectura?: number
          tokens_entrada?: number
          tokens_salida?: number
          usuario_id?: string | null
        }
        Update: {
          conversacion_id?: string | null
          costo_usd?: number
          created_at?: string
          id?: string
          inmobiliaria_id?: string
          modelo?: string
          tokens_cache_escritura?: number
          tokens_cache_lectura?: number
          tokens_entrada?: number
          tokens_salida?: number
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bi_uso_conversacion_id_fkey"
            columns: ["conversacion_id"]
            isOneToOne: false
            referencedRelation: "bi_conversaciones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bi_uso_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bi_uso_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      captacion_cola: {
        Row: {
          created_at: string
          estado: string
          fuente: string
          fuente_id: string | null
          id: string
          inmobiliaria_id: string
          precio: number | null
          prospecto_id: string | null
          titulo: string | null
          updated_at: string
          url: string
        }
        Insert: {
          created_at?: string
          estado?: string
          fuente: string
          fuente_id?: string | null
          id?: string
          inmobiliaria_id: string
          precio?: number | null
          prospecto_id?: string | null
          titulo?: string | null
          updated_at?: string
          url: string
        }
        Update: {
          created_at?: string
          estado?: string
          fuente?: string
          fuente_id?: string | null
          id?: string
          inmobiliaria_id?: string
          precio?: number | null
          prospecto_id?: string | null
          titulo?: string | null
          updated_at?: string
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "captacion_cola_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "captacion_cola_prospecto_id_fkey"
            columns: ["prospecto_id"]
            isOneToOne: false
            referencedRelation: "captacion_prospectos"
            referencedColumns: ["id"]
          },
        ]
      }
      captacion_prospectos: {
        Row: {
          area_m2: number | null
          asesor_id: string | null
          banos: number | null
          barrio: string | null
          base_tratamiento: string | null
          canal: string | null
          ciudad: string | null
          confianza_particular: number | null
          contacto_nombre: string | null
          contacto_perfil: string | null
          contacto_telefono: string | null
          created_at: string
          descripcion: string | null
          es_dueno_directo: boolean | null
          estado: string
          fecha_captura: string | null
          fecha_contacto: string | null
          fuente: string
          fuente_id: string | null
          habitaciones: number | null
          id: string
          inmobiliaria_id: string
          inmueble_id: string | null
          mensaje_borrador: string | null
          motivos: string | null
          n_seguimientos: number
          notas: string | null
          opt_out: boolean
          origen_dato: string | null
          precio: number | null
          proximo_seguimiento: string | null
          score: number | null
          tipo_inmueble: string | null
          tipo_transaccion: string | null
          titulo: string | null
          updated_at: string
          url: string | null
        }
        Insert: {
          area_m2?: number | null
          asesor_id?: string | null
          banos?: number | null
          barrio?: string | null
          base_tratamiento?: string | null
          canal?: string | null
          ciudad?: string | null
          confianza_particular?: number | null
          contacto_nombre?: string | null
          contacto_perfil?: string | null
          contacto_telefono?: string | null
          created_at?: string
          descripcion?: string | null
          es_dueno_directo?: boolean | null
          estado?: string
          fecha_captura?: string | null
          fecha_contacto?: string | null
          fuente: string
          fuente_id?: string | null
          habitaciones?: number | null
          id?: string
          inmobiliaria_id: string
          inmueble_id?: string | null
          mensaje_borrador?: string | null
          motivos?: string | null
          n_seguimientos?: number
          notas?: string | null
          opt_out?: boolean
          origen_dato?: string | null
          precio?: number | null
          proximo_seguimiento?: string | null
          score?: number | null
          tipo_inmueble?: string | null
          tipo_transaccion?: string | null
          titulo?: string | null
          updated_at?: string
          url?: string | null
        }
        Update: {
          area_m2?: number | null
          asesor_id?: string | null
          banos?: number | null
          barrio?: string | null
          base_tratamiento?: string | null
          canal?: string | null
          ciudad?: string | null
          confianza_particular?: number | null
          contacto_nombre?: string | null
          contacto_perfil?: string | null
          contacto_telefono?: string | null
          created_at?: string
          descripcion?: string | null
          es_dueno_directo?: boolean | null
          estado?: string
          fecha_captura?: string | null
          fecha_contacto?: string | null
          fuente?: string
          fuente_id?: string | null
          habitaciones?: number | null
          id?: string
          inmobiliaria_id?: string
          inmueble_id?: string | null
          mensaje_borrador?: string | null
          motivos?: string | null
          n_seguimientos?: number
          notas?: string | null
          opt_out?: boolean
          origen_dato?: string | null
          precio?: number | null
          proximo_seguimiento?: string | null
          score?: number | null
          tipo_inmueble?: string | null
          tipo_transaccion?: string | null
          titulo?: string | null
          updated_at?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "captacion_prospectos_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "captacion_prospectos_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "captacion_prospectos_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "franjas_inmuebles"
            referencedColumns: ["inmueble_id"]
          },
          {
            foreignKeyName: "captacion_prospectos_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      captacion_uso: {
        Row: {
          costo_usd: number
          created_at: string
          id: string
          inmobiliaria_id: string
          modelo: string
          prospecto_id: string | null
          tokens_cache: number
          tokens_entrada: number
          tokens_salida: number
        }
        Insert: {
          costo_usd?: number
          created_at?: string
          id?: string
          inmobiliaria_id: string
          modelo: string
          prospecto_id?: string | null
          tokens_cache?: number
          tokens_entrada?: number
          tokens_salida?: number
        }
        Update: {
          costo_usd?: number
          created_at?: string
          id?: string
          inmobiliaria_id?: string
          modelo?: string
          prospecto_id?: string | null
          tokens_cache?: number
          tokens_entrada?: number
          tokens_salida?: number
        }
        Relationships: [
          {
            foreignKeyName: "captacion_uso_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "captacion_uso_prospecto_id_fkey"
            columns: ["prospecto_id"]
            isOneToOne: false
            referencedRelation: "captacion_prospectos"
            referencedColumns: ["id"]
          },
        ]
      }
      citas: {
        Row: {
          alcance: string
          aptos_snapshot: Json | null
          cliente_email: string | null
          cliente_nombre: string
          cliente_telefono: string
          completada_at: string | null
          completada_por: string | null
          confirmada_at: string | null
          confirmada_por: string | null
          created_at: string
          estado: string
          fecha: string
          franja_id: string
          hora_fin: string
          hora_inicio: string
          id: string
          inmobiliaria_id: string
          inmueble_id: string
          notas: string | null
          origen: string
          unidad: string | null
        }
        Insert: {
          alcance?: string
          aptos_snapshot?: Json | null
          cliente_email?: string | null
          cliente_nombre: string
          cliente_telefono: string
          completada_at?: string | null
          completada_por?: string | null
          confirmada_at?: string | null
          confirmada_por?: string | null
          created_at?: string
          estado?: string
          fecha: string
          franja_id: string
          hora_fin: string
          hora_inicio: string
          id?: string
          inmobiliaria_id: string
          inmueble_id: string
          notas?: string | null
          origen?: string
          unidad?: string | null
        }
        Update: {
          alcance?: string
          aptos_snapshot?: Json | null
          cliente_email?: string | null
          cliente_nombre?: string
          cliente_telefono?: string
          completada_at?: string | null
          completada_por?: string | null
          confirmada_at?: string | null
          confirmada_por?: string | null
          created_at?: string
          estado?: string
          fecha?: string
          franja_id?: string
          hora_fin?: string
          hora_inicio?: string
          id?: string
          inmobiliaria_id?: string
          inmueble_id?: string
          notas?: string | null
          origen?: string
          unidad?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "citas_completada_por_fkey"
            columns: ["completada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "citas_confirmada_por_fkey"
            columns: ["confirmada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "citas_franja_id_fkey"
            columns: ["franja_id"]
            isOneToOne: false
            referencedRelation: "franjas_horarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "citas_franja_id_fkey"
            columns: ["franja_id"]
            isOneToOne: false
            referencedRelation: "franjas_inmuebles"
            referencedColumns: ["franja_id"]
          },
          {
            foreignKeyName: "citas_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "citas_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "franjas_inmuebles"
            referencedColumns: ["inmueble_id"]
          },
          {
            foreignKeyName: "citas_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      franjas_horarias: {
        Row: {
          asesor_id: string
          color: string | null
          creado_por: string
          created_at: string
          fecha: string
          hora_fin: string
          hora_inicio: string
          id: string
          inmobiliaria_id: string
          inmueble_id: string
        }
        Insert: {
          asesor_id: string
          color?: string | null
          creado_por: string
          created_at?: string
          fecha: string
          hora_fin: string
          hora_inicio: string
          id?: string
          inmobiliaria_id: string
          inmueble_id: string
        }
        Update: {
          asesor_id?: string
          color?: string | null
          creado_por?: string
          created_at?: string
          fecha?: string
          hora_fin?: string
          hora_inicio?: string
          id?: string
          inmobiliaria_id?: string
          inmueble_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "franjas_horarias_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "franjas_horarias_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "franjas_horarias_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "franjas_horarias_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "franjas_inmuebles"
            referencedColumns: ["inmueble_id"]
          },
          {
            foreignKeyName: "franjas_horarias_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      inmobiliarias: {
        Row: {
          created_at: string
          id: string
          nit: string
          nombre: string
        }
        Insert: {
          created_at?: string
          id?: string
          nit: string
          nombre: string
        }
        Update: {
          created_at?: string
          id?: string
          nit?: string
          nombre?: string
        }
        Relationships: []
      }
      inmuebles: {
        Row: {
          arrendasoft_contrato_id: string | null
          arrendasoft_contrato_info: Json | null
          arrendasoft_id: number | null
          asesor_id: string | null
          asesor_id_override: string | null
          banos: number | null
          barrio: string | null
          ciudad: string | null
          created_at: string
          descripcion: string | null
          direccion: string
          empalme_contacto_nombre: string | null
          empalme_contacto_telefono: string | null
          estado: string
          estado_erp: string | null
          estado_override: string | null
          habitaciones: number | null
          id: string
          imagenes: Json | null
          inmobiliaria_id: string
          precio: number
          precio_oferta: number | null
          tipo_inmueble: string
          tipo_transaccion: string
          titulo: string
          unidad: string | null
        }
        Insert: {
          arrendasoft_contrato_id?: string | null
          arrendasoft_contrato_info?: Json | null
          arrendasoft_id?: number | null
          asesor_id?: string | null
          asesor_id_override?: string | null
          banos?: number | null
          barrio?: string | null
          ciudad?: string | null
          created_at?: string
          descripcion?: string | null
          direccion: string
          empalme_contacto_nombre?: string | null
          empalme_contacto_telefono?: string | null
          estado?: string
          estado_erp?: string | null
          estado_override?: string | null
          habitaciones?: number | null
          id?: string
          imagenes?: Json | null
          inmobiliaria_id: string
          precio: number
          precio_oferta?: number | null
          tipo_inmueble: string
          tipo_transaccion: string
          titulo: string
          unidad?: string | null
        }
        Update: {
          arrendasoft_contrato_id?: string | null
          arrendasoft_contrato_info?: Json | null
          arrendasoft_id?: number | null
          asesor_id?: string | null
          asesor_id_override?: string | null
          banos?: number | null
          barrio?: string | null
          ciudad?: string | null
          created_at?: string
          descripcion?: string | null
          direccion?: string
          empalme_contacto_nombre?: string | null
          empalme_contacto_telefono?: string | null
          estado?: string
          estado_erp?: string | null
          estado_override?: string | null
          habitaciones?: number | null
          id?: string
          imagenes?: Json | null
          inmobiliaria_id?: string
          precio?: number
          precio_oferta?: number | null
          tipo_inmueble?: string
          tipo_transaccion?: string
          titulo?: string
          unidad?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inmuebles_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inmuebles_asesor_id_override_fkey"
            columns: ["asesor_id_override"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inmuebles_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
        ]
      }
      integraciones_mercadolibre: {
        Row: {
          access_token: string
          conectado_por: string | null
          created_at: string
          expires_at: string
          id: string
          inmobiliaria_id: string
          ml_nickname: string | null
          ml_user_id: string | null
          refresh_token: string
          scope: string | null
          updated_at: string
        }
        Insert: {
          access_token: string
          conectado_por?: string | null
          created_at?: string
          expires_at: string
          id?: string
          inmobiliaria_id: string
          ml_nickname?: string | null
          ml_user_id?: string | null
          refresh_token: string
          scope?: string | null
          updated_at?: string
        }
        Update: {
          access_token?: string
          conectado_por?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          inmobiliaria_id?: string
          ml_nickname?: string | null
          ml_user_id?: string | null
          refresh_token?: string
          scope?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "integraciones_mercadolibre_conectado_por_fkey"
            columns: ["conectado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integraciones_mercadolibre_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: true
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
        ]
      }
      inventarios: {
        Row: {
          arrendasoft_contrato_id: string | null
          cedula_asesor_metadata: Json | null
          cedula_asesor_url: string | null
          cedula_inquilino_metadata: Json | null
          cedula_inquilino_url: string | null
          contrato_id_propuesto: string | null
          creado_por: string | null
          created_at: string
          estado: string
          firma_asesor_url: string | null
          firma_inquilino_url: string | null
          firmado_at: string | null
          id: string
          inmueble_id: string
          items: Json
          selfie_asesor_url: string | null
          selfie_inquilino_url: string | null
          titulo: string
        }
        Insert: {
          arrendasoft_contrato_id?: string | null
          cedula_asesor_metadata?: Json | null
          cedula_asesor_url?: string | null
          cedula_inquilino_metadata?: Json | null
          cedula_inquilino_url?: string | null
          contrato_id_propuesto?: string | null
          creado_por?: string | null
          created_at?: string
          estado?: string
          firma_asesor_url?: string | null
          firma_inquilino_url?: string | null
          firmado_at?: string | null
          id?: string
          inmueble_id: string
          items: Json
          selfie_asesor_url?: string | null
          selfie_inquilino_url?: string | null
          titulo: string
        }
        Update: {
          arrendasoft_contrato_id?: string | null
          cedula_asesor_metadata?: Json | null
          cedula_asesor_url?: string | null
          cedula_inquilino_metadata?: Json | null
          cedula_inquilino_url?: string | null
          contrato_id_propuesto?: string | null
          creado_por?: string | null
          created_at?: string
          estado?: string
          firma_asesor_url?: string | null
          firma_inquilino_url?: string | null
          firmado_at?: string | null
          id?: string
          inmueble_id?: string
          items?: Json
          selfie_asesor_url?: string | null
          selfie_inquilino_url?: string | null
          titulo?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventarios_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventarios_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "franjas_inmuebles"
            referencedColumns: ["inmueble_id"]
          },
          {
            foreignKeyName: "inventarios_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      solicitudes_apertura: {
        Row: {
          alcance: string
          cita_id: string | null
          cliente_email: string | null
          cliente_nombre: string
          cliente_telefono: string
          created_at: string
          decidido_at: string | null
          decidido_por: string | null
          estado: string
          fecha: string
          hora_fin: string
          hora_inicio: string
          id: string
          inmobiliaria_id: string
          inmueble_id: string
          motivo_denegacion: string | null
          notas: string | null
          tipo_transaccion: string | null
          unidad: string | null
        }
        Insert: {
          alcance?: string
          cita_id?: string | null
          cliente_email?: string | null
          cliente_nombre: string
          cliente_telefono: string
          created_at?: string
          decidido_at?: string | null
          decidido_por?: string | null
          estado?: string
          fecha: string
          hora_fin: string
          hora_inicio: string
          id?: string
          inmobiliaria_id: string
          inmueble_id: string
          motivo_denegacion?: string | null
          notas?: string | null
          tipo_transaccion?: string | null
          unidad?: string | null
        }
        Update: {
          alcance?: string
          cita_id?: string | null
          cliente_email?: string | null
          cliente_nombre?: string
          cliente_telefono?: string
          created_at?: string
          decidido_at?: string | null
          decidido_por?: string | null
          estado?: string
          fecha?: string
          hora_fin?: string
          hora_inicio?: string
          id?: string
          inmobiliaria_id?: string
          inmueble_id?: string
          motivo_denegacion?: string | null
          notas?: string | null
          tipo_transaccion?: string | null
          unidad?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "solicitudes_apertura_cita_id_fkey"
            columns: ["cita_id"]
            isOneToOne: false
            referencedRelation: "citas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_apertura_decidido_por_fkey"
            columns: ["decidido_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_apertura_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_apertura_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "franjas_inmuebles"
            referencedColumns: ["inmueble_id"]
          },
          {
            foreignKeyName: "solicitudes_apertura_inmueble_id_fkey"
            columns: ["inmueble_id"]
            isOneToOne: false
            referencedRelation: "inmuebles"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas: {
        Row: {
          completada_at: string | null
          completada_por: string | null
          created_at: string
          entidad_id: string | null
          entidad_tipo: string
          estado: string
          evento_origen: string | null
          evento_titulo: string
          id: string
          inmobiliaria_id: string
          titulo: string
          usuario_id: string | null
        }
        Insert: {
          completada_at?: string | null
          completada_por?: string | null
          created_at?: string
          entidad_id?: string | null
          entidad_tipo?: string
          estado?: string
          evento_origen?: string | null
          evento_titulo: string
          id?: string
          inmobiliaria_id: string
          titulo: string
          usuario_id?: string | null
        }
        Update: {
          completada_at?: string | null
          completada_por?: string | null
          created_at?: string
          entidad_id?: string | null
          entidad_tipo?: string
          estado?: string
          evento_origen?: string | null
          evento_titulo?: string
          id?: string
          inmobiliaria_id?: string
          titulo?: string
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_completada_por_fkey"
            columns: ["completada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuarios: {
        Row: {
          created_at: string
          email: string
          id: string
          inmobiliaria_id: string
          nombre_completo: string
          rol: string
          telefono: string | null
        }
        Insert: {
          created_at?: string
          email: string
          id: string
          inmobiliaria_id: string
          nombre_completo: string
          rol: string
          telefono?: string | null
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          inmobiliaria_id?: string
          nombre_completo?: string
          rol?: string
          telefono?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "usuarios_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_logs: {
        Row: {
          asesor_nombre: string
          created_at: string
          error_detalles: string | null
          estado: string
          files_count: number
          files_size_bytes: number
          id: string
          inmobiliaria_id: string
          payload: Json
          precio: number
          titulo_captacion: string
          usuario_id: string | null
        }
        Insert: {
          asesor_nombre: string
          created_at?: string
          error_detalles?: string | null
          estado?: string
          files_count?: number
          files_size_bytes?: number
          id?: string
          inmobiliaria_id: string
          payload: Json
          precio: number
          titulo_captacion: string
          usuario_id?: string | null
        }
        Update: {
          asesor_nombre?: string
          created_at?: string
          error_detalles?: string | null
          estado?: string
          files_count?: number
          files_size_bytes?: number
          id?: string
          inmobiliaria_id?: string
          payload?: Json
          precio?: number
          titulo_captacion?: string
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "webhook_logs_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_logs_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      franjas_inmuebles: {
        Row: {
          asesor_id: string | null
          fecha: string | null
          franja_id: string | null
          hora_fin: string | null
          hora_inicio: string | null
          inmobiliaria_id: string | null
          inmueble_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "franjas_horarias_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "franjas_horarias_inmobiliaria_id_fkey"
            columns: ["inmobiliaria_id"]
            isOneToOne: false
            referencedRelation: "inmobiliarias"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      agendar_cita: {
        Args: {
          p_alcance?: string
          p_aptos_snapshot?: Json
          p_cliente_email?: string
          p_cliente_nombre: string
          p_cliente_telefono: string
          p_fecha: string
          p_hora_fin: string
          p_hora_inicio: string
          p_inmueble_id: string
          p_notas?: string
          p_unidad?: string
        }
        Returns: Json
      }
      agendar_cita_por_texto: {
        Args: {
          p_alcance?: string
          p_cliente_email?: string
          p_cliente_nombre: string
          p_cliente_telefono: string
          p_fecha: string
          p_hora_fin: string
          p_hora_inicio: string
          p_notas?: string
          p_texto: string
          p_tipo_transaccion?: string
        }
        Returns: Json
      }
      agente_comercial_pausado: {
        Args: { p_inmobiliaria: string }
        Returns: boolean
      }
      buscar_inmueble_por_codigo: { Args: { p_codigo: string }; Returns: Json }
      cancelar_cita: {
        Args: { p_cita_id: string; p_cliente_telefono: string }
        Returns: Json
      }
      consultar_disponibilidad: {
        Args: {
          p_fecha_desde?: string
          p_fecha_hasta?: string
          p_inmueble_id: string
        }
        Returns: {
          asesor: string
          fecha: string
          franja_id: string
          hora_fin: string
          hora_inicio: string
        }[]
      }
      consultar_disponibilidad_por_texto: {
        Args: {
          p_fecha_desde?: string
          p_fecha_hasta?: string
          p_texto: string
          p_tipo_transaccion?: string
        }
        Returns: {
          aptos: Json
          aptos_count: number
          asesor: string
          direccion: string
          fecha: string
          franja_id: string
          hora_fin: string
          hora_inicio: string
          inmueble_id: string
          modo: string
          titulo: string
          unidad: string
        }[]
      }
      crear_tarea_actualizar_inmuebles: { Args: never; Returns: undefined }
      get_my_inmobiliaria: { Args: never; Returns: string }
      get_my_role: { Args: never; Returns: string }
      marcar_cita_realizada: { Args: { p_cita_id: string }; Returns: Json }
      resolver_inmuebles_por_texto: {
        Args: { p_texto: string; p_tipo_transaccion?: string }
        Returns: {
          banos: number
          direccion: string
          habitaciones: number
          id: string
          precio: number
          tipo_transaccion: string
          titulo: string
          unidad: string
        }[]
      }
      solicitar_apertura_agenda: {
        Args: {
          p_alcance?: string
          p_cliente_email?: string
          p_cliente_nombre: string
          p_cliente_telefono: string
          p_fecha: string
          p_hora_fin: string
          p_hora_inicio: string
          p_notas?: string
          p_texto: string
          p_tipo_transaccion?: string
        }
        Returns: Json
      }
      ubicacion_key: {
        Args: { p_direccion: string; p_unidad: string }
        Returns: string
      }
      unaccent: { Args: { "": string }; Returns: string }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  crm: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

