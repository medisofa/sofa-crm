/** SOFA · Estados de la cita: un solo juego de nombres y colores para el día, la semana y recepción. */
export const APPT_STATUS = {
  programada: ['Programada', 'info'], confirmada: ['Confirmada', 'ok'], en_espera: ['En espera', 'warn'], en_consulta: ['En consulta', 'warn'],
  atendida: ['Atendida', ''], no_asistio: ['No asistió', 'bad'], cancelada: ['Cancelada', '']
};
/** Color de la tarjeta en las cuadrículas (css/app.css, .wk-ap). */
export const STATUS_CLS = { programada: 'p', confirmada: 'c', en_espera: 'e', en_consulta: 'e', atendida: 'd', no_asistio: 'd', cancelada: 'd' };
