BEGIN;

-- ==========================================
-- 0. CONFIGURACIÓN INICIAL Y TIPOS
-- ==========================================
-- Habilitamos la extensión para generar UUIDs criptográficos
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Definimos Tipos de Datos (ENUMS)
CREATE TYPE tipo_archivo AS ENUM ('AUDIO', 'VIDEO', 'IMAGEN', 'PICTOGRAMA', 'TTS');
CREATE TYPE sentimiento_ia AS ENUM ('FRUSTRADO', 'NEUTRO', 'FELIZ', 'CONCENTRADO', 'DISTRAIDO');

-- ==========================================
-- 1. SISTEMA DE ROLES (RBAC)
-- ==========================================

CREATE TABLE roles (
    id_rol UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre_rol VARCHAR(50) UNIQUE NOT NULL, -- Ej: 'TUTOR', 'FONOAUDIOLOGO', 'PEDIATRA'
    descripcion TEXT,
    permisos_app JSONB DEFAULT '{}'::jsonb, -- Ej: {"ver_reportes": true, "editar_actividades": false}
    is_active BOOLEAN DEFAULT TRUE
);

-- ==========================================
-- 2. USUARIOS ADULTOS (Tutores y Profesionales)
-- ==========================================
CREATE TABLE usuarios (
    id_usuario UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_rol UUID NOT NULL REFERENCES roles(id_rol),
    
    -- Datos compartidos por TODOS los que inician sesión
    nombre_completo VARCHAR(150) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, 
    
    is_verified BOOLEAN DEFAULT FALSE,
    ultimo_acceso TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tutores (
    id_tutor UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario UUID UNIQUE NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    telefono_contacto VARCHAR(20),

	-- Nuevos campos agregados
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE profesionales (
    id_profesional UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario UUID UNIQUE NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    especialidad VARCHAR(100) NOT NULL, 
    cedula_profesional VARCHAR(50), 
    institucion_clinica VARCHAR(150)
);

-- ==========================================
-- 3. PERFIL DEL NIÑO Y ASIGNACIONES CLÍNICAS
-- ==========================================
CREATE TABLE ninos (
    id_nino UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_tutor UUID NOT NULL REFERENCES tutores(id_tutor) ON DELETE CASCADE,
    alias VARCHAR(50) NOT NULL,
    fecha_nacimiento DATE NOT NULL,
    
    -- Perfil cognitivo y médico flexible (JSON)
    perfil_cognitivo JSONB DEFAULT '{}'::jsonb,
    
    -- Preferencias de interfaz (contraste, tamaño de fuente)
    configuracion_accesibilidad JSONB DEFAULT '{"tamano_fuente": "grande", "modo_daltonico": false}'::jsonb,
    
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tabla Puente: Un niño puede tener varios terapeutas, y un terapeuta varios niños
CREATE TABLE asignaciones_terapeuticas (
    id_asignacion UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_nino UUID NOT NULL REFERENCES ninos(id_nino) ON DELETE CASCADE,
    id_profesional UUID NOT NULL REFERENCES profesionales(id_profesional) ON DELETE CASCADE,
    objetivo_principal TEXT, 
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT unique_asignacion UNIQUE (id_nino, id_profesional)
);

-- ==========================================
-- 4. CATÁLOGO DE ACTIVIDADES Y MULTIMEDIA
-- ==========================================
CREATE TABLE actividades (
    id_actividad UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo VARCHAR(100) NOT NULL,
    descripcion TEXT,
    nivel_dificultad SMALLINT CHECK (nivel_dificultad BETWEEN 1 AND 10),
    tags TEXT[], -- Ej: ["motricidad_fina", "animales", "atencion_visual"]
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE recursos_multimedia (
    id_recurso UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_actividad UUID REFERENCES actividades(id_actividad) ON DELETE CASCADE,
    tipo tipo_archivo NOT NULL,
    url_storage TEXT NOT NULL, 
    metadata_tecnica JSONB DEFAULT '{}'::jsonb,
    orden_secuencia SMALLINT DEFAULT 0,
    texto_accesible TEXT 
);

-- ==========================================
-- 5. HISTORIAL DE JUEGO (Log Transaccional)
-- ==========================================
CREATE TABLE sesiones_actividad (
    id_sesion UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_nino UUID NOT NULL REFERENCES ninos(id_nino) ON DELETE CASCADE,
    id_actividad UUID NOT NULL REFERENCES actividades(id_actividad) ON DELETE CASCADE,
    
    fecha_inicio TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    fecha_fin TIMESTAMP WITH TIME ZONE,
    completado BOOLEAN DEFAULT FALSE,
    tiempo_total_segundos INTEGER,
    intentos_fallidos INTEGER DEFAULT 0,
    
    -- Mapa de calor de interacciones en pantalla
    heatmap_interaccion JSONB
);

-- ==========================================
-- 6. INTELIGENCIA ARTIFICIAL Y SUPERVISIÓN (Human-in-the-Loop)
-- ==========================================
CREATE TABLE ia_insights (
    id_insight UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_sesion UUID UNIQUE REFERENCES sesiones_actividad(id_sesion) ON DELETE CASCADE,
    
    modelo_ia_version VARCHAR(50),
    emocion_predominante sentimiento_ia,
    nivel_atencion_score DECIMAL(5,2), 
    
    -- Vector embeddings para recomendaciones (RAG)
    vector_comportamiento FLOAT[], 
    
    recomendacion_generada TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE supervisiones_profesionales (
    id_supervision UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_sesion UUID NOT NULL REFERENCES sesiones_actividad(id_sesion) ON DELETE CASCADE,
    id_profesional UUID NOT NULL REFERENCES profesionales(id_profesional) ON DELETE CASCADE,
    
    ia_acertada BOOLEAN, -- Feedback para reentrenar el modelo
    notas_clinicas TEXT, 
    ajuste_dificultad_sugerido SMALLINT, 
    
    fecha_revision TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- 7. ÍNDICES (Para velocidad y escalabilidad)
-- ==========================================
CREATE INDEX idx_nino_perfil ON ninos USING GIN (perfil_cognitivo);
CREATE INDEX idx_sesion_fecha ON sesiones_actividad (fecha_inicio DESC);
CREATE INDEX idx_actividad_tags ON actividades USING GIN (tags);
CREATE INDEX idx_asignacion_nino ON asignaciones_terapeuticas (id_nino);
CREATE INDEX idx_asignacion_profesional ON asignaciones_terapeuticas (id_profesional);

-- ==========================================
-- 8. TRIGGERS AUTOMÁTICOS (Para updated_at)
-- ==========================================
-- Función (ya la tienes, se mantiene igual)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Tus triggers actualizados
CREATE TRIGGER update_usuario_modtime BEFORE UPDATE ON usuarios FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_nino_modtime BEFORE UPDATE ON ninos FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- NUEVO TRIGGER PARA TUTORES
CREATE TRIGGER update_tutor_modtime BEFORE UPDATE ON tutores FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

COMMIT;


BEGIN;

-- ==========================================
-- 1. INSERTAR ROLES Y USUARIOS (Contexto del Proyecto)
-- ==========================================
-- Aseguramos que existan los roles
INSERT INTO roles (nombre_rol, descripcion, permisos_app) 
VALUES 
('TUTOR_PRINCIPAL', 'Padre o cuidador principal en casa', '{"ver_reportes": true, "editar_actividades": false}'::jsonb),
('ESPECIALISTA_INCLUSION', 'Terapeuta enfocado en intervención temprana', '{"ver_reportes": true, "crear_rutinas": true}'::jsonb)
ON CONFLICT (nombre_rol) DO NOTHING;

-- Usuarios de prueba
INSERT INTO usuarios (id_rol, nombre_completo, email, password_hash, is_verified) VALUES
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR_PRINCIPAL'), 'Ana Laura López', 'ana.lopez@email.com', 'hash_1', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'ESPECIALISTA_INCLUSION'), 'Lic. Roberto Torres', 'rtorres@terapia.com', 'hash_2', true);

INSERT INTO tutores (id_usuario, telefono_contacto) VALUES
((SELECT id_usuario FROM usuarios WHERE email = 'ana.lopez@email.com'), '+522711234567');

INSERT INTO profesionales (id_usuario, especialidad, cedula_profesional, institucion_clinica) VALUES
((SELECT id_usuario FROM usuarios WHERE email = 'rtorres@terapia.com'), 'Educación Especial e Intervención Temprana', 'CED-112233', 'Centro de Inclusión UTCV');

-- ==========================================
-- 2. PERFILES DE NIÑOS CON SÍNDROME DE DOWN
-- ==========================================
-- Perfil 1: Enfoque en desarrollo de autonomía y rutinas diarias
INSERT INTO ninos (id_tutor, alias, fecha_nacimiento, perfil_cognitivo, configuracion_accesibilidad) VALUES
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'ana.lopez@email.com'), 
    'Sofía', 
    '2018-08-10', 
    '{
        "estilo_aprendizaje": "visual_kinestesico", 
        "nivel_atencion_promedio_minutos": 12, 
        "fortalezas": ["memoria_visual", "empatia", "imitacion"],
        "areas_oportunidad": ["motricidad_fina", "lenguaje_expresivo"],
        "requiere_apoyo_visual": true
    }'::jsonb,
    '{"tamano_fuente": "grande", "modo_daltonico": false, "interfaz_simplificada": true}'::jsonb
);

-- ==========================================
-- 3. ASIGNACIONES CLÍNICAS (Objetivos de la investigación)
-- ==========================================
INSERT INTO asignaciones_terapeuticas (id_nino, id_profesional, objetivo_principal) VALUES
(
    (SELECT id_nino FROM ninos WHERE alias = 'Sofía'),
    (SELECT id_profesional FROM profesionales JOIN usuarios u ON profesionales.id_usuario = u.id_usuario WHERE u.email = 'rtorres@terapia.com'),
    'Desarrollar autonomía en el lavado de manos y mejorar la comunicación mediante pictogramas interactivos.'
);

-- ==========================================
-- 4. ACTIVIDADES EDUCATIVAS Y DE VIDA DIARIA
-- ==========================================
-- Actividad 1: Autonomía (Rutinas diarias)
INSERT INTO actividades (titulo, descripcion, nivel_dificultad, tags) VALUES
('Rutina: Lavado de Manos', 'Secuencia visual paso a paso para el lavado correcto de manos.', 2, ARRAY['autonomia', 'vida_diaria', 'secuencias', 'autocuidado']),
('Asociación de Palabras e Imágenes', 'Relacionar objetos cotidianos con su pictograma y sonido correspondiente.', 3, ARRAY['comunicacion', 'lenguaje', 'visual', 'cognitivo']);

-- Recursos multimedia (Pictogramas esenciales para aprendizaje visual)
INSERT INTO recursos_multimedia (id_actividad, tipo, url_storage, orden_secuencia, texto_accesible) VALUES
((SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Lavado de Manos'), 'PICTOGRAMA', 'https://storage.app.com/picto_jabon.png', 1, 'Tomar el jabón'),
((SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Lavado de Manos'), 'PICTOGRAMA', 'https://storage.app.com/picto_agua.png', 2, 'Enjuagar con agua'),
((SELECT id_actividad FROM actividades WHERE titulo = 'Asociación de Palabras e Imágenes'), 'AUDIO', 'https://storage.app.com/audio_manzana.mp3', 1, 'Voz clara diciendo Manzana');

-- ==========================================
-- 5. HISTORIAL DE SESIONES (Seguimiento del progreso)
-- ==========================================
-- Sesión simulando el uso de la actividad de autonomía
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
(
    (SELECT id_nino FROM ninos WHERE alias = 'Sofía'),
    (SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Lavado de Manos'),
    CURRENT_TIMESTAMP - INTERVAL '1 day', 
    TRUE, 
    320, -- 5 minutos aprox
    2, 
    '{"zonas_toque": [{"x": 150, "y": 200, "tipo": "error_arrastre"}, {"x": 400, "y": 200, "tipo": "acierto"}]}'::jsonb
),
-- Sesión de comunicación
(
    (SELECT id_nino FROM ninos WHERE alias = 'Sofía'),
    (SELECT id_actividad FROM actividades WHERE titulo = 'Asociación de Palabras e Imágenes'),
    CURRENT_TIMESTAMP, 
    FALSE, 
    180, 
    4, 
    '{"zonas_toque": [{"x": 100, "y": 100, "tipo": "multiples_toques_rapidos"}]}'::jsonb
);

-- ==========================================
-- 6. IA INSIGHTS Y SUPERVISIÓN (Continuidad del cuidado)
-- ==========================================
-- Insight de la primera sesión (Éxito)
INSERT INTO ia_insights (id_sesion, modelo_ia_version, emocion_predominante, nivel_atencion_score, vector_comportamiento, recomendacion_generada) VALUES
(
    (SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 320 LIMIT 1),
    'edu-down-v1.0',
    'FELIZ',
    7.8,
    ARRAY[0.4, 0.6, 0.1, 0.8, 0.2],
    'El usuario completó la secuencia de autonomía con éxito tras dos intentos. Refuerzo positivo detectado. Sugerencia: Mantener nivel de dificultad.'
);

-- Insight de la segunda sesión (Frustración por comunicación)
INSERT INTO ia_insights (id_sesion, modelo_ia_version, emocion_predominante, nivel_atencion_score, vector_comportamiento, recomendacion_generada) VALUES
(
    (SELECT id_sesion FROM sesiones_actividad WHERE completado = FALSE LIMIT 1),
    'edu-down-v1.0',
    'FRUSTRADO',
    4.2,
    ARRAY[-0.5, 0.2, 0.9, -0.4, 0.1],
    'Se detectaron toques repetitivos rápidos y caída en la atención. Sugerencia: Reducir la cantidad de elementos en pantalla de 4 a 2 opciones.'
);

-- Validación del terapeuta (Fomentando la comunicación entre cuidador y terapeuta)
INSERT INTO supervisiones_profesionales (id_sesion, id_profesional, ia_acertada, notas_clinicas, ajuste_dificultad_sugerido) VALUES
(
    (SELECT id_sesion FROM sesiones_actividad WHERE completado = FALSE LIMIT 1),
    (SELECT id_profesional FROM profesionales JOIN usuarios u ON profesionales.id_usuario = u.id_usuario WHERE u.email = 'rtorres@terapia.com'),
    TRUE,
    'De acuerdo con la IA. Sofía muestra sobrecarga visual cuando hay más de 3 pictogramas. Ajustaré la configuración de accesibilidad para la familia en casa.',
    -1
);

COMMIT;











-- Mas datos

BEGIN;

-- ==========================================
-- 1. ASEGURAR ROLES EXISTENTES
-- ==========================================
INSERT INTO roles (nombre_rol, descripcion, permisos_app) VALUES
('TUTOR', 'Familiar o cuidador principal', '{"ver_reportes": true, "editar_actividades": false}'::jsonb),
('TERAPEUTA', 'Especialista clínico o educador', '{"ver_reportes": true, "editar_actividades": true}'::jsonb),
('ADMINISTRADOR', 'Gestor de la plataforma', '{"ver_todo": true, "gestionar_usuarios": true}'::jsonb)
ON CONFLICT (nombre_rol) DO NOTHING;

-- ==========================================
-- 2. INSERCIÓN MASIVA DE USUARIOS (Adultos)
-- ==========================================
-- TUTORES
INSERT INTO usuarios (id_rol, nombre_completo, email, password_hash, is_verified) VALUES
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Carmen Salinas', 'carmen.s@email.com', 'hash_t1', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Jorge Medina', 'jorge.m@email.com', 'hash_t2', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Elena Rojas', 'elena.r@email.com', 'hash_t3', true);

INSERT INTO tutores (id_usuario, telefono_contacto) VALUES
((SELECT id_usuario FROM usuarios WHERE email = 'carmen.s@email.com'), '+525550001111'),
((SELECT id_usuario FROM usuarios WHERE email = 'jorge.m@email.com'), '+525550002222'),
((SELECT id_usuario FROM usuarios WHERE email = 'elena.r@email.com'), '+525550003333');

-- PROFESIONALES
INSERT INTO usuarios (id_rol, nombre_completo, email, password_hash, is_verified) VALUES
((SELECT id_rol FROM roles WHERE nombre_rol = 'TERAPEUTA'), 'Dra. Patricia Vega', 'p.vega@terapia.com', 'hash_p1', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TERAPEUTA'), 'Lic. Andrés Fuentes', 'a.fuentes@terapia.com', 'hash_p2', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TERAPEUTA'), 'Mtra. Silvia Ortiz', 's.ortiz@escuela.com', 'hash_p3', true);

INSERT INTO profesionales (id_usuario, especialidad, cedula_profesional, institucion_clinica) VALUES
((SELECT id_usuario FROM usuarios WHERE email = 'p.vega@terapia.com'), 'Fonoaudiología y Lenguaje', 'CED-10101', 'Centro Médico Integral'),
((SELECT id_usuario FROM usuarios WHERE email = 'a.fuentes@terapia.com'), 'Terapia Ocupacional', 'CED-20202', 'Clínica de Desarrollo Infantil'),
((SELECT id_usuario FROM usuarios WHERE email = 's.ortiz@escuela.com'), 'Educación Especial', 'CED-30303', 'Instituto de Inclusión Educativa');

-- ==========================================
-- 3. PERFILES DE NIÑOS CON SÍNDROME DE DOWN
-- ==========================================
INSERT INTO ninos (id_tutor, alias, fecha_nacimiento, perfil_cognitivo, configuracion_accesibilidad) VALUES
-- Niño 1: Enfoque visual, requiere alto contraste
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'carmen.s@email.com'), 
    'Mateo', '2017-04-12', 
    '{"estilo_aprendizaje": "visual", "nivel_atencion_minutos": 15, "fortalezas": ["reconocimiento_patrones"], "sensibilidad_auditiva": "alta"}'::jsonb,
    '{"tamano_fuente": "extra_grande", "alto_contraste": true, "volumen_predeterminado": "bajo"}'::jsonb
),
-- Niña 2: Enfoque kinestésico, usa pictogramas
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'jorge.m@email.com'), 
    'Valeria', '2019-11-05', 
    '{"estilo_aprendizaje": "kinestesico", "nivel_atencion_minutos": 10, "fortalezas": ["imitacion_motora", "empatia"]}'::jsonb,
    '{"tamano_fuente": "grande", "animaciones_reducidas": true, "tipo_interaccion": "tocar_no_arrastrar"}'::jsonb
),
-- Niño 3: Desarrollo de lenguaje expresivo
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'elena.r@email.com'), 
    'Diego', '2018-02-20', 
    '{"estilo_aprendizaje": "auditivo_visual", "nivel_atencion_minutos": 12, "fortalezas": ["memoria_musical"]}'::jsonb,
    '{"tamano_fuente": "normal", "lector_pantalla_tts": true}'::jsonb
);

-- ==========================================
-- 4. RED DE ASIGNACIONES (Varios profesionales por niño)
-- ==========================================
INSERT INTO asignaciones_terapeuticas (id_nino, id_profesional, objetivo_principal, fecha_inicio) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Mateo'), (SELECT id_profesional FROM profesionales JOIN usuarios u ON u.id_usuario = profesionales.id_usuario WHERE u.email = 'p.vega@terapia.com'), 'Mejorar articulación de fonemas', CURRENT_DATE - 60),
((SELECT id_nino FROM ninos WHERE alias = 'Mateo'), (SELECT id_profesional FROM profesionales JOIN usuarios u ON u.id_usuario = profesionales.id_usuario WHERE u.email = 'a.fuentes@terapia.com'), 'Motricidad fina para escritura', CURRENT_DATE - 45),
((SELECT id_nino FROM ninos WHERE alias = 'Valeria'), (SELECT id_profesional FROM profesionales JOIN usuarios u ON u.id_usuario = profesionales.id_usuario WHERE u.email = 'a.fuentes@terapia.com'), 'Autonomía en el vestido', CURRENT_DATE - 30),
((SELECT id_nino FROM ninos WHERE alias = 'Diego'), (SELECT id_profesional FROM profesionales JOIN usuarios u ON u.id_usuario = profesionales.id_usuario WHERE u.email = 's.ortiz@escuela.com'), 'Reconocimiento de números 1 al 5', CURRENT_DATE - 15);

-- ==========================================
-- 5. GRAN CATÁLOGO DE ACTIVIDADES
-- ==========================================
INSERT INTO actividades (titulo, descripcion, nivel_dificultad, tags) VALUES
('Rutina: Cepillado de Dientes', 'Secuencia visual para lavado dental correcto', 2, ARRAY['autonomia', 'higiene', 'secuencias']),
('Clasificador de Tamaños', 'Separar pelotas grandes y pequeñas', 3, ARRAY['cognitivo', 'tamaños', 'motricidad_fina']),
('Sonidos de la Granja', 'Asociar el sonido con el animal correspondiente', 1, ARRAY['lenguaje', 'auditivo', 'animales']),
('Emociones: ¿Cómo me siento?', 'Identificar expresiones faciales básicas', 4, ARRAY['inteligencia_emocional', 'social', 'empatia']),
('Trazos Divertidos', 'Seguir la línea punteada para mejorar el pulso', 5, ARRAY['motricidad_fina', 'pre_escritura']);

-- Recursos multimedia masivos
INSERT INTO recursos_multimedia (id_actividad, tipo, url_storage, orden_secuencia, texto_accesible) VALUES
((SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Cepillado de Dientes'), 'PICTOGRAMA', 'https://storage/cepillo.png', 1, 'Tomar el cepillo'),
((SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Cepillado de Dientes'), 'PICTOGRAMA', 'https://storage/pasta.png', 2, 'Poner pasta dental'),
((SELECT id_actividad FROM actividades WHERE titulo = 'Sonidos de la Granja'), 'AUDIO', 'https://storage/vaca.mp3', 1, 'Muuuu'),
((SELECT id_actividad FROM actividades WHERE titulo = 'Sonidos de la Granja'), 'IMAGEN', 'https://storage/vaca_foto.jpg', 2, 'Foto de vaca'),
((SELECT id_actividad FROM actividades WHERE titulo = 'Emociones: ¿Cómo me siento?'), 'VIDEO', 'https://storage/nino_riendo.mp4', 1, 'Niño riendo a carcajadas');

-- ==========================================
-- 6. HISTORIAL DE SESIONES (Simulando una semana de uso)
-- ==========================================
-- Sesiones de Mateo (Hace 3 días)
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_inicio, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Mateo'), (SELECT id_actividad FROM actividades WHERE titulo = 'Sonidos de la Granja'), CURRENT_TIMESTAMP - INTERVAL '3 days', CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '3 minutes', TRUE, 180, 0, '{"clicks_rapidos": false, "precision": 95}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Mateo'), (SELECT id_actividad FROM actividades WHERE titulo = 'Trazos Divertidos'), CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '6 minutes', FALSE, 360, 5, '{"zona_conflicto": "esquina_superior_derecha", "salida_de_trazo": 12}'::jsonb);

-- Sesiones de Valeria
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_inicio, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Valeria'), (SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Cepillado de Dientes'), CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '4 minutes', TRUE, 240, 1, '{"tiempo_pausa_promedio": 5}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Valeria'), (SELECT id_actividad FROM actividades WHERE titulo = 'Clasificador de Tamaños'), CURRENT_TIMESTAMP - INTERVAL '12 hours', CURRENT_TIMESTAMP - INTERVAL '12 hours' + INTERVAL '5 minutes', TRUE, 300, 2, '{"elementos_arrastrados": 8}'::jsonb);

-- Sesión de Diego (Hoy)
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_inicio, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Diego'), (SELECT id_actividad FROM actividades WHERE titulo = 'Emociones: ¿Cómo me siento?'), CURRENT_TIMESTAMP - INTERVAL '1 hour', CURRENT_TIMESTAMP - INTERVAL '50 minutes', TRUE, 600, 3, '{"toques_en_pantalla": 45}'::jsonb);

-- ==========================================
-- 7. IA INSIGHTS (Análisis del comportamiento)
-- ==========================================
INSERT INTO ia_insights (id_sesion, modelo_ia_version, emocion_predominante, nivel_atencion_score, vector_comportamiento, recomendacion_generada) VALUES
-- Insight Mateo fallando trazos
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 360 LIMIT 1), 'edu-down-v2', 'FRUSTRADO', 3.5, ARRAY[-0.8, -0.5, 0.9, 0.1, -0.2], 'Se detectó dificultad sostenida en la motricidad fina. Reducir la sensibilidad del trazo y aumentar el grosor de la línea en un 50%.'),
-- Insight Valeria logrando rutina
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 240 LIMIT 1), 'edu-down-v2', 'FELIZ', 8.9, ARRAY[0.6, 0.7, -0.2, 0.9, 0.5], 'Secuencia de rutina completada exitosamente. Excelente ritmo de interacción. Recomendar transición a rutina de vestido.');

-- ==========================================
-- 8. SUPERVISIÓN Y NOTAS CLÍNICAS (Human-in-the-loop)
-- ==========================================
INSERT INTO supervisiones_profesionales (id_sesion, id_profesional, ia_acertada, notas_clinicas, ajuste_dificultad_sugerido) VALUES
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 360 LIMIT 1), (SELECT id_profesional FROM profesionales JOIN usuarios u ON u.id_usuario = profesionales.id_usuario WHERE u.email = 'a.fuentes@terapia.com'), TRUE, 'La sugerencia de la IA es correcta. Mateo necesita trazos más gruesos en la interfaz para no frustrarse. Modificaré su perfil en la app.', -2),
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 240 LIMIT 1), (SELECT id_profesional FROM profesionales JOIN usuarios u ON u.id_usuario = profesionales.id_usuario WHERE u.email = 'p.vega@terapia.com'), TRUE, 'Buen progreso en casa según lo reportado por la plataforma. Felicitar a la mamá en la próxima consulta.', 1);

COMMIT;


ROLLBACK;





BEGIN;

-- ==========================================
-- 1. MÁS USUARIOS: TUTORES Y PROFESIONALES
-- ==========================================
INSERT INTO usuarios (id_rol, nombre_completo, email, password_hash, is_verified) VALUES
-- Nuevos Tutores
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Roberto Gómez', 'roberto.g@email.com', 'hash_t4', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Lucía Méndez', 'lucia.m@email.com', 'hash_t5', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Fernando Ayala', 'fernando.a@email.com', 'hash_t6', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TUTOR'), 'Diana Reyes', 'diana.r@email.com', 'hash_t7', true),
-- Nuevos Profesionales
((SELECT id_rol FROM roles WHERE nombre_rol = 'TERAPEUTA'), 'Dr. Mario Bros', 'mario.b@terapia.com', 'hash_p4', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TERAPEUTA'), 'Lic. Sara Connor', 'sara.c@escuela.com', 'hash_p5', true),
((SELECT id_rol FROM roles WHERE nombre_rol = 'TERAPEUTA'), 'Mtro. Tony Stark', 'tony.s@clinica.com', 'hash_p6', true);

INSERT INTO tutores (id_usuario, telefono_contacto) VALUES
((SELECT id_usuario FROM usuarios WHERE email = 'roberto.g@email.com'), '+525551114444'),
((SELECT id_usuario FROM usuarios WHERE email = 'lucia.m@email.com'), '+525551115555'),
((SELECT id_usuario FROM usuarios WHERE email = 'fernando.a@email.com'), '+525551116666'),
((SELECT id_usuario FROM usuarios WHERE email = 'diana.r@email.com'), '+525551117777');

INSERT INTO profesionales (id_usuario, especialidad, cedula_profesional, institucion_clinica) VALUES
((SELECT id_usuario FROM usuarios WHERE email = 'mario.b@terapia.com'), 'Psicomotricidad', 'CED-40404', 'Centro de Movimiento Libre'),
((SELECT id_usuario FROM usuarios WHERE email = 'sara.c@escuela.com'), 'Educación Inclusiva', 'CED-50505', 'Instituto de Integración'),
((SELECT id_usuario FROM usuarios WHERE email = 'tony.s@clinica.com'), 'Ingeniería Biomédica Aplicada', 'CED-60606', 'Laboratorio de Innovación Educativa');

-- ==========================================
-- 2. UNA TROPILLA DE NIÑOS CON PERFILES DIVERSOS
-- ==========================================
INSERT INTO ninos (id_tutor, alias, fecha_nacimiento, perfil_cognitivo, configuracion_accesibilidad) VALUES
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'roberto.g@email.com'), 
    'Hugo', '2016-09-15', 
    '{"estilo_aprendizaje": "visual_auditivo", "nivel_atencion_minutos": 20, "fortalezas": ["memoria_a_corto_plazo", "sociabilidad"], "necesita_refuerzo": "lectoescritura"}'::jsonb,
    '{"tamano_fuente": "grande", "alto_contraste": false, "lector_pantalla_tts": true}'::jsonb
),
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'lucia.m@email.com'), 
    'Paco', '2018-05-30', 
    '{"estilo_aprendizaje": "kinestesico", "nivel_atencion_minutos": 8, "fortalezas": ["motricidad_gruesa", "energia"], "necesita_refuerzo": "resolucion_problemas"}'::jsonb,
    '{"tamano_fuente": "extra_grande", "animaciones_reducidas": false, "gamificacion_activa": true}'::jsonb
),
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'fernando.a@email.com'), 
    'Luis', '2019-01-10', 
    '{"estilo_aprendizaje": "visual", "nivel_atencion_minutos": 12, "fortalezas": ["reconocimiento_facial", "imitacion"], "necesita_refuerzo": "autonomia_vestido"}'::jsonb,
    '{"tamano_fuente": "normal", "alto_contraste": true, "iconos_simplificados": true}'::jsonb
),
(
    (SELECT id_tutor FROM tutores JOIN usuarios u ON tutores.id_usuario = u.id_usuario WHERE u.email = 'diana.r@email.com'), 
    'Emma', '2020-11-22', 
    '{"estilo_aprendizaje": "auditivo", "nivel_atencion_minutos": 15, "fortalezas": ["lenguaje_receptivo", "atencion_sostenida"], "necesita_refuerzo": "motricidad_fina"}'::jsonb,
    '{"tamano_fuente": "grande", "volumen_predeterminado": "alto", "colores_pastel": true}'::jsonb
);

-- ==========================================
-- 3. CATÁLOGO EXPANDIDO DE ACTIVIDADES (Gamificación y Educación)
-- ==========================================
INSERT INTO actividades (titulo, descripcion, nivel_dificultad, tags) VALUES
('Matemáticas: Contando Manzanas', 'Arrastrar el número correcto de manzanas a la canasta', 3, ARRAY['matematicas', 'numeros', 'gamificacion']),
('Lectoescritura: Vocales Mágicas', 'Identificar la vocal con la que empieza la palabra', 4, ARRAY['lectoescritura', 'lenguaje', 'visual']),
('Habilidades Sociales: Saludar', 'Secuencia de pasos para saludar a un amigo', 2, ARRAY['social', 'comunicacion', 'interaccion']),
('Rompecabezas de Animales', 'Armar figuras geométricas básicas', 5, ARRAY['resolucion_problemas', 'cognitivo', 'espacial']),
('Rutina: Preparar la mochila', 'Seleccionar los objetos necesarios para ir a la escuela', 6, ARRAY['autonomia', 'vida_diaria', 'memoria']);

-- ==========================================
-- 4. SIMULACIÓN DE TRÁFICO MASIVO (Historial de Sesiones)
-- ==========================================
-- Inyectamos múltiples sesiones para "Hugo" (Enfoque en Lectoescritura y Matemáticas)
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_inicio, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Hugo'), (SELECT id_actividad FROM actividades WHERE titulo = 'Lectoescritura: Vocales Mágicas'), CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP - INTERVAL '10 days' + INTERVAL '8 minutes', TRUE, 480, 2, '{"precision_toque": 85, "zonas_calientes": ["centro", "inferior_derecho"]}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Hugo'), (SELECT id_actividad FROM actividades WHERE titulo = 'Lectoescritura: Vocales Mágicas'), CURRENT_TIMESTAMP - INTERVAL '8 days', CURRENT_TIMESTAMP - INTERVAL '8 days' + INTERVAL '6 minutes', TRUE, 360, 1, '{"precision_toque": 90, "mejora_tiempo": true}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Hugo'), (SELECT id_actividad FROM actividades WHERE titulo = 'Matemáticas: Contando Manzanas'), CURRENT_TIMESTAMP - INTERVAL '5 days', CURRENT_TIMESTAMP - INTERVAL '5 days' + INTERVAL '12 minutes', FALSE, 720, 6, '{"precision_toque": 40, "frustracion_detectada_por_toques_rapidos": true}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Hugo'), (SELECT id_actividad FROM actividades WHERE titulo = 'Matemáticas: Contando Manzanas'), CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '9 minutes', TRUE, 540, 3, '{"precision_toque": 75, "arrastre_completado": true}'::jsonb);

-- Inyectamos sesiones para "Paco" (Enfoque en problemas y motricidad)
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_inicio, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Paco'), (SELECT id_actividad FROM actividades WHERE titulo = 'Rompecabezas de Animales'), CURRENT_TIMESTAMP - INTERVAL '15 days', CURRENT_TIMESTAMP - INTERVAL '15 days' + INTERVAL '15 minutes', FALSE, 900, 10, '{"abandono_prematuro": true, "piezas_movidas": 15}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Paco'), (SELECT id_actividad FROM actividades WHERE titulo = 'Rompecabezas de Animales'), CURRENT_TIMESTAMP - INTERVAL '14 days', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '10 minutes', TRUE, 600, 4, '{"abandono_prematuro": false, "piezas_movidas": 25}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Paco'), (SELECT id_actividad FROM actividades WHERE titulo = 'Rutina: Preparar la mochila'), CURRENT_TIMESTAMP - INTERVAL '7 days', CURRENT_TIMESTAMP - INTERVAL '7 days' + INTERVAL '5 minutes', TRUE, 300, 0, '{"secuencia_perfecta": true}'::jsonb);

-- Inyectamos sesiones para "Emma" (Enfoque en audición y social)
INSERT INTO sesiones_actividad (id_nino, id_actividad, fecha_inicio, fecha_fin, completado, tiempo_total_segundos, intentos_fallidos, heatmap_interaccion) VALUES
((SELECT id_nino FROM ninos WHERE alias = 'Emma'), (SELECT id_actividad FROM actividades WHERE titulo = 'Habilidades Sociales: Saludar'), CURRENT_TIMESTAMP - INTERVAL '4 days', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '4 minutes', TRUE, 240, 1, '{"tiempo_reaccion_audio": "1.2s"}'::jsonb),
((SELECT id_nino FROM ninos WHERE alias = 'Emma'), (SELECT id_actividad FROM actividades WHERE titulo = 'Habilidades Sociales: Saludar'), CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '3 minutes', TRUE, 180, 0, '{"tiempo_reaccion_audio": "0.8s"}'::jsonb);

-- ==========================================
-- 5. UNA AVALANCHA DE INSIGHTS DE IA Y SUPERVISIÓN
-- ==========================================
INSERT INTO ia_insights (id_sesion, modelo_ia_version, emocion_predominante, nivel_atencion_score, vector_comportamiento, recomendacion_generada) VALUES
-- Hugo fallando matemáticas
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 720 AND completado = FALSE LIMIT 1), 'edu-down-v3', 'FRUSTRADO', 2.1, ARRAY[-0.9, -0.8, 0.5, 0.2, -0.1], 'Alta tasa de error al arrastrar objetos. Posible fatiga cognitiva. Se sugiere cambiar a una actividad de refuerzo visual sin arrastre.'),
-- Hugo logrando matemáticas después
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 540 AND completado = TRUE LIMIT 1), 'edu-down-v3', 'CONCENTRADO', 7.5, ARRAY[0.4, 0.5, 0.1, 0.7, 0.3], 'Mejora significativa en la precisión del arrastre. Mantener nivel actual.'),
-- Paco logrando la mochila perfecto
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 300 AND completado = TRUE LIMIT 1), 'edu-down-v3', 'FELIZ', 9.8, ARRAY[0.8, 0.9, -0.1, 0.8, 0.6], 'Memoria secuencial excelente. Listo para agregar más variables (objetos) a la mochila.');

INSERT INTO supervisiones_profesionales (id_sesion, id_profesional, ia_acertada, notas_clinicas, ajuste_dificultad_sugerido) VALUES
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 720 AND completado = FALSE LIMIT 1), (SELECT id_profesional FROM profesionales WHERE especialidad = 'Psicomotricidad' LIMIT 1), TRUE, 'Coincido con la IA. Hugo se frustró por la exigencia motriz fina de arrastrar. Ajustaremos la app para que las manzanas se seleccionen con un solo toque (tap) en lugar de arrastre (drag).', -1),
((SELECT id_sesion FROM sesiones_actividad WHERE tiempo_total_segundos = 300 AND completado = TRUE LIMIT 1), (SELECT id_profesional FROM profesionales WHERE especialidad = 'Educación Inclusiva' LIMIT 1), TRUE, 'Excelente retención de la rutina diaria. Notificaré a los padres para que repliquen esto con la mochila real en casa.', 2);

COMMIT;