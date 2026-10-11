import { MeasureError, distance, floorplanSVG, polygon, resultFor, validatePoints, validateProject, validateScale } from './measure.js';
import { assessTransport } from './transport.js';
import { applianceCatalog } from './appliance-catalog.js';
import { experienceText } from './experience-i18n.js';

const escapeHTML = value => String(value).replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
const dxNumber = value => Object.is(value, -0) ? '0' : String(Number(value.toPrecision(12)));
// Keep group values on a single line and preserve Unicode in pre-2007 ASCII DXF.
// Escape literal percent/backslash so labels cannot become CAD text control codes.
function dxText(value) {
  return String(value).replace(/[\x00-\x1f\x7f]/g, ' ').replace(/[\\%\u0080-\uffff]/g, character => `\\U+${character.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')}`);
}

/** AutoCAD 2000 ASCII DXF. Coordinates and dimensions use meters ($INSUNITS=6).
 * CAD X = viewer X, CAD Y = -viewer Z. Each floor is a closed LWPOLYLINE.
 * Dimensions are deliberately independent LINE/TEXT entities, not associative
 * CAD dimensions or BIM objects. Editing the contour in CAD does not update text.
 * Specification: Autodesk DXF HEADER, LWPOLYLINE and TEXT reference pages:
 * https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DXF/files/GUID-A85E8E67-27CD-4C59-BE61-4DC9FADBE74A.htm
 * https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DXF/files/GUID-748FC305-F3F2-4F74-825A-61F04D757A50.htm
 * https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DXF/files/GUID-62E5383D-8A14-47B4-BFC4-35824CAE8363.htm
 */
export function floorplanDXF(measurements, scale, name = 'Floor plan') {
  validateScale(scale);
  if (!Array.isArray(measurements) || measurements.length > 500 || typeof name !== 'string' || name.length > 200) throw new MeasureError('invalidProject');
  const floors = measurements.filter(measurement => measurement.kind === 'floor');
  if (!floors.length) throw new MeasureError('noFloor');
  const outlines = floors.map(measurement => {
    if (typeof measurement.label !== 'string' || measurement.label.length > 200) throw new MeasureError('invalidProject');
    const metrics = polygon(measurement.points, scale, 'floor');
    return { ...measurement, metrics, points2D: measurement.points.map(point => [point[0] * scale, -point[2] * scale]) };
  });
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const outline of outlines) for (const [x, y] of outline.points2D) { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); }
  const span = Math.max(maxX - minX, maxY - minY, 0.01), textHeight = span * 0.014, offset = span * 0.05;
  let nextHandle = 0x20;
  const handle = () => (nextHandle++).toString(16).toUpperCase();
  const code = (target, ...pairs) => { for (let i = 0; i < pairs.length; i += 2) target.push(String(pairs[i]), typeof pairs[i + 1] === 'number' ? dxNumber(pairs[i + 1]) : String(pairs[i + 1])); };
  const tables = [], blocks = [], entities = [], objects = [];
  const table = (type, count) => { const id = handle(); code(tables, 0, 'TABLE', 2, type, 5, id, 330, '0', 100, 'AcDbSymbolTable', 70, count); return id; };
  const linetypeTable = table('LTYPE', 1);
  code(tables, 0, 'LTYPE', 5, handle(), 330, linetypeTable, 100, 'AcDbSymbolTableRecord', 100, 'AcDbLinetypeTableRecord', 2, 'CONTINUOUS', 70, 0, 3, 'Solid line', 72, 65, 73, 0, 40, 0, 0, 'ENDTAB');
  const layerTable = table('LAYER', 4);
  for (const [layer, color] of [['0', 7], ['KANTURA_FLOOR', 7], ['KANTURA_DIMENSION', 5], ['KANTURA_LABEL', 3]]) code(tables, 0, 'LAYER', 5, handle(), 330, layerTable, 100, 'AcDbSymbolTableRecord', 100, 'AcDbLayerTableRecord', 2, layer, 70, 0, 62, color, 6, 'CONTINUOUS');
  code(tables, 0, 'ENDTAB');
  const styleTable = table('STYLE', 1);
  code(tables, 0, 'STYLE', 5, handle(), 330, styleTable, 100, 'AcDbSymbolTableRecord', 100, 'AcDbTextStyleTableRecord', 2, 'STANDARD', 70, 0, 40, 0, 41, 1, 50, 0, 71, 0, 42, textHeight, 3, 'arial.ttf', 4, '', 0, 'ENDTAB');
  const blockTable = table('BLOCK_RECORD', 2), modelRecord = handle(), paperRecord = handle();
  for (const [id, blockName] of [[modelRecord, '*Model_Space'], [paperRecord, '*Paper_Space']]) code(tables, 0, 'BLOCK_RECORD', 5, id, 330, blockTable, 100, 'AcDbSymbolTableRecord', 100, 'AcDbBlockTableRecord', 2, blockName);
  code(tables, 0, 'ENDTAB');
  for (const [id, blockName] of [[modelRecord, '*Model_Space'], [paperRecord, '*Paper_Space']]) code(blocks, 0, 'BLOCK', 5, handle(), 330, id, 100, 'AcDbEntity', 8, '0', 100, 'AcDbBlockBegin', 2, blockName, 70, 0, 10, 0, 20, 0, 30, 0, 3, blockName, 1, '', 0, 'ENDBLK', 5, handle(), 330, id, 100, 'AcDbEntity', 8, '0', 100, 'AcDbBlockEnd');
  const entity = (type, layer, subclass) => code(entities, 0, type, 5, handle(), 330, modelRecord, 100, 'AcDbEntity', 8, layer, 100, subclass);
  const line = (a, b) => { entity('LINE', 'KANTURA_DIMENSION', 'AcDbLine'); code(entities, 10, a[0], 20, a[1], 30, 0, 11, b[0], 21, b[1], 31, 0); };
  const text = (value, point, height = textHeight, rotation = 0, centered = false, layer = 'KANTURA_LABEL') => {
    entity('TEXT', layer, 'AcDbText');
    code(entities, 10, point[0], 20, point[1], 30, 0, 40, height, 1, dxText(value), 50, rotation, 7, 'STANDARD', 72, centered ? 1 : 0, 11, point[0], 21, point[1], 31, 0, 100, 'AcDbText', 73, centered ? 2 : 0);
  };
  for (const outline of outlines) {
    const points = outline.points2D;
    entity('LWPOLYLINE', 'KANTURA_FLOOR', 'AcDbPolyline'); code(entities, 90, points.length, 70, 1, 38, 0);
    for (const point of points) code(entities, 10, point[0], 20, point[1]);
    const signedArea = points.reduce((sum, point, index) => { const next = points[(index + 1) % points.length]; return sum + point[0] * next[1] - next[0] * point[1]; }, 0);
    const winding = signedArea >= 0 ? 1 : -1;
    for (let index = 0; index < points.length; index++) {
      const a = points[index], b = points[(index + 1) % points.length], dx = b[0] - a[0], dy = b[1] - a[1], length = Math.hypot(dx, dy);
      const normal = [winding * dy / length, -winding * dx / length];
      const shift = (point, amount) => [point[0] + normal[0] * amount, point[1] + normal[1] * amount];
      const da = shift(a, offset), db = shift(b, offset);
      line(shift(a, offset * 0.1), shift(a, offset * 1.18)); line(shift(b, offset * 0.1), shift(b, offset * 1.18)); line(da, db);
      const tick = textHeight * 0.5, tangent = [dx / length, dy / length];
      for (const p of [da, db]) line([p[0] - (normal[0] + tangent[0]) * tick, p[1] - (normal[1] + tangent[1]) * tick], [p[0] + (normal[0] + tangent[0]) * tick, p[1] + (normal[1] + tangent[1]) * tick]);
      let rotation = Math.atan2(dy, dx) * 180 / Math.PI;
      if (rotation > 90) rotation -= 180; else if (rotation < -90) rotation += 180;
      text(`${length.toFixed(3)} m`, shift([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2], offset + textHeight), textHeight, rotation, true, 'KANTURA_DIMENSION');
    }
    const center = points.reduce((sum, point) => [sum[0] + point[0] / points.length, sum[1] + point[1] / points.length], [0, 0]);
    text(outline.label, [center[0], center[1] + textHeight], textHeight * 1.1, 0, true);
    text(`${outline.metrics.area.toFixed(3)} m2 | P ${outline.metrics.perimeter.toFixed(3)} m`, [center[0], center[1] - textHeight], textHeight, 0, true);
  }
  text(`KANTURA | ${name}`, [minX, maxY + offset * 3], textHeight * 1.5);
  text('1 drawing unit = 1 m | floor outlines from captured or selected contours', [minX, maxY + offset * 2], textHeight);
  text('Independent dimension labels: editing CAD geometry does not update labels.', [minX, minY - offset * 3], textHeight);
  code(objects, 0, 'DICTIONARY', 5, handle(), 330, '0', 100, 'AcDbDictionary', 281, 1);
  const output = [];
  code(output, 999, 'KANTURA: metric floor plan; coordinates already include the project scale.', 0, 'SECTION', 2, 'HEADER', 9, '$ACADVER', 1, 'AC1015', 9, '$DWGCODEPAGE', 3, 'ANSI_1252', 9, '$INSUNITS', 70, 6, 9, '$MEASUREMENT', 70, 1, 9, '$LUNITS', 70, 2, 9, '$LUPREC', 70, 3, 9, '$HANDSEED', 5, nextHandle.toString(16).toUpperCase(), 9, '$EXTMIN', 10, minX - offset * 2, 20, minY - offset * 4, 30, 0, 9, '$EXTMAX', 10, maxX + offset * 2, 20, maxY + offset * 4, 30, 0, 0, 'ENDSEC');
  for (const [section, contents] of [['TABLES', tables], ['BLOCKS', blocks], ['ENTITIES', entities], ['OBJECTS', objects]]) { code(output, 0, 'SECTION', 2, section); for (const entry of contents) output.push(entry); code(output, 0, 'ENDSEC'); }
  code(output, 0, 'EOF');
  return output.join('\r\n') + '\r\n';
}

const labels = {
  de: { report: 'Messbericht', print: 'Drucken / als PDF speichern', date: 'Erstellt (UTC)', project: 'Projekt', reference: 'Referenzstatus', calibrated: 'Mit Referenz kalibriert', unverified: 'Maßstab noch nicht geprüft', scale: 'Meter pro Modelleinheit', measurements: 'Messungen', name: 'Bezeichnung', type: 'Typ', length: 'Länge', horizontal: 'Horizontal', vertical: 'Höhenunterschied', area: 'Fläche', perimeter: 'Umfang', distance: 'Strecke', floor: 'Grundfläche', surface: 'Oberfläche', floorplan: 'Grundriss', floorNote: 'KANTURA · Bodenkonturen · Maße in Metern · anhand einer Referenz prüfen', notes: 'Notizen und Fotos', position: 'Position im Modell (m)', door: 'Tür', window: 'Fenster', gate: 'Tor', wall: 'Wand', other: 'Sonstiges', checks: 'Referenzvergleiche', known: 'Bekannte Länge', measured: 'Gemessen', deviation: 'Differenz', relative: 'Differenz (%)', empty: 'Keine Messungen vorhanden.', note: 'Die Werte stammen aus den markierten Scanpunkten. Eine globale Kalibrierung behebt keine lokalen Scanfehler. Referenzdifferenzen sind keine Genauigkeitsgarantie.', planNote: 'Grundriss schematisch. Für Maße die Beschriftungen verwenden; der Ausdruck hat keinen festen Maßstab.', pdfHint: 'Im Druckdialog als Ziel „Als PDF speichern“ wählen.', noPhoto: 'Foto nicht in diesen Bericht eingebettet.' },
  fr: { report: 'Rapport de mesures', print: 'Imprimer / enregistrer en PDF', date: 'Créé (UTC)', project: 'Projet', reference: 'État de la référence', calibrated: 'Étalonné avec une référence', unverified: 'Échelle non vérifiée', scale: 'Mètres par unité du modèle', measurements: 'Mesures', name: 'Libellé', type: 'Type', length: 'Longueur', horizontal: 'Horizontale', vertical: 'Différence de hauteur', area: 'Surface', perimeter: 'Périmètre', distance: 'Distance', floor: 'Surface au sol', surface: 'Surface plane', floorplan: 'Plan', floorNote: 'KANTURA · contours du sol · mesures en mètres · vérifier avec une référence', notes: 'Notes et photos', position: 'Position dans le modèle (m)', door: 'Porte', window: 'Fenêtre', gate: 'Portail', wall: 'Mur', other: 'Autre', checks: 'Comparaisons de référence', known: 'Longueur connue', measured: 'Mesurée', deviation: 'Écart', relative: 'Écart (%)', empty: 'Aucune mesure.', note: 'Les valeurs proviennent des points marqués dans le scan. Un étalonnage global ne corrige pas les erreurs locales du scan. Les écarts de référence ne garantissent pas la précision.', planNote: 'Plan schématique. Utilisez les cotes ; l’impression n’a pas d’échelle fixe.', pdfHint: 'Choisissez « Enregistrer au format PDF » dans la boîte de dialogue d’impression.', noPhoto: 'Photo non intégrée à ce rapport.' },
  es: { report: 'Informe de medidas', print: 'Imprimir / guardar como PDF', date: 'Creado (UTC)', project: 'Proyecto', reference: 'Estado de referencia', calibrated: 'Calibrado con referencia', unverified: 'Escala sin verificar', scale: 'Metros por unidad del modelo', measurements: 'Medidas', name: 'Nombre', type: 'Tipo', length: 'Longitud', horizontal: 'Horizontal', vertical: 'Diferencia de altura', area: 'Área', perimeter: 'Perímetro', distance: 'Distancia', floor: 'Superficie del suelo', surface: 'Superficie plana', floorplan: 'Plano', floorNote: 'KANTURA · contornos del suelo · medidas en metros · comprobar con una referencia', notes: 'Notas y fotos', position: 'Posición en el modelo (m)', door: 'Puerta', window: 'Ventana', gate: 'Portón', wall: 'Pared', other: 'Otro', checks: 'Comparaciones de referencia', known: 'Longitud conocida', measured: 'Medida', deviation: 'Diferencia', relative: 'Diferencia (%)', empty: 'No hay medidas.', note: 'Los valores proceden de los puntos marcados en el escaneo. Una calibración global no corrige errores locales. Las diferencias de referencia no garantizan la precisión.', planNote: 'Plano esquemático. Utiliza las cotas; la impresión no tiene una escala fija.', pdfHint: 'Elige « Guardar como PDF » en el diálogo de impresión.', noPhoto: 'La foto no se ha incluido en este informe.' },
  it: { report: 'Rapporto di misura', print: 'Stampa / salva come PDF', date: 'Creato (UTC)', project: 'Progetto', reference: 'Stato del riferimento', calibrated: 'Calibrato con riferimento', unverified: 'Scala non verificata', scale: 'Metri per unità del modello', measurements: 'Misure', name: 'Nome', type: 'Tipo', length: 'Lunghezza', horizontal: 'Orizzontale', vertical: 'Dislivello', area: 'Area', perimeter: 'Perimetro', distance: 'Distanza', floor: 'Area del pavimento', surface: 'Superficie piana', floorplan: 'Pianta', floorNote: 'KANTURA · tracciato manuale · misure in metri · verificare con un riferimento', notes: 'Note e foto', position: 'Posizione nel modello (m)', door: 'Porta', window: 'Finestra', gate: 'Cancello', wall: 'Parete', other: 'Altro', checks: 'Confronti con riferimenti', known: 'Lunghezza nota', measured: 'Misurata', deviation: 'Differenza', relative: 'Differenza (%)', empty: 'Nessuna misura.', note: 'I valori provengono dai punti segnati nella scansione. Una calibrazione globale non corregge gli errori locali. Le differenze dei riferimenti non garantiscono la precisione.', planNote: 'Pianta schematica. Utilizzare le quote; la stampa non ha una scala fissa.', pdfHint: 'Scegli « Salva come PDF » nella finestra di stampa.', noPhoto: 'Foto non incorporata nel rapporto.' },
  'zh-Hans': { report: '测量报告', print: '打印 / 另存为 PDF', date: '生成时间（UTC）', project: '项目', reference: '参考校准状态', calibrated: '已按参考长度校准', unverified: '比例尚未核验', scale: '每个模型单位对应的米数', measurements: '测量结果', name: '名称', type: '类型', length: '长度', horizontal: '水平距离', vertical: '高度差', area: '面积', perimeter: '周长', distance: '距离', floor: '地面面积', surface: '平面表面积', floorplan: '平面图', floorNote: 'KANTURA · 地面轮廓 · 尺寸单位为米 · 请用参考长度核验', notes: '注释与照片', position: '模型中的位置（米）', door: '门', window: '窗', gate: '大门', wall: '墙', other: '其他', checks: '参考长度对比', known: '已知长度', measured: '测得长度', deviation: '差值', relative: '差值（%）', empty: '暂无测量结果。', note: '数值来自扫描中标记的点。整体比例校准无法修复局部扫描误差。参考差值不代表精度保证。', planNote: '此为示意平面图。请以尺寸标注为准；打印件没有固定比例。', pdfHint: '在打印对话框中选择“另存为 PDF”。', noPhoto: '此照片未嵌入报告。' }
};
const reportLanguage = language => { const value = String(language).toLowerCase(); return value.startsWith('zh') ? 'zh-Hans' : Object.keys(labels).find(key => value === key || value.startsWith(`${key}-`)) || 'de'; };

const transportLabels = {
  de: { title: 'Transportabschätzung', model: 'Modell / Gegenstand', recorded: 'Gespeicherte Eingaben (UTC)', recalculated: 'Beim Berichtsexport aus den gespeicherten Eingaben neu berechnet. Dies ist eine konservative Hüllraumprüfung, keine Bestätigung eines kollisionsfreien oder sicheren Transportwegs.', inputs: 'Verwendete Eingaben', scenario: 'Geprüfte Orientierung', startingYaw: 'Ausgangsdrehung', tilt: 'Kippwinkel', stairAngle: 'Treppenneigung', clearances: 'Verbleibende Abstände der gewählten Orientierung', clearance: 'Restabstand (m)', reasons: 'Begründung', assumptions: 'Annahmen und Grenzen', yes: 'Ja', no: 'Nein', manual: 'Manuell eingegebene Maße; keine eindeutige Katalogzuordnung.', catalogNotice: 'Der Herstellerlink ist eine Referenz zum Modell. Gerechnet wird mit den untenstehenden gespeicherten Maßen; diese können von Katalogmaßen abweichen. Katalogmaße sind ohne Verpackung. Tatsächliche Außenmaße einschließlich Griffen, Verpackung und Transporthilfen sowie die zulässige Transportlage prüfen.', upright: 'Aufrecht', 'upright-sideways': 'Aufrecht, seitlich gedreht', 'stair-tilt': 'An der Treppenneigung gekippt', 'stair-tilt-sideways': 'Seitlich gedreht und an der Treppenneigung gekippt' },
  fr: { title: 'Estimation du transport', model: 'Modèle / objet', recorded: 'Données enregistrées (UTC)', recalculated: 'Recalculé lors de l’export du rapport à partir des données enregistrées. Il s’agit d’une vérification conservative des volumes, pas d’une confirmation d’un trajet sans collision ou d’un transport sûr.', inputs: 'Données utilisées', scenario: 'Orientation vérifiée', startingYaw: 'Rotation initiale', tilt: 'Inclinaison', stairAngle: 'Pente de l’escalier', clearances: 'Marges restantes pour l’orientation choisie', clearance: 'Marge restante (m)', reasons: 'Motifs', assumptions: 'Hypothèses et limites', yes: 'Oui', no: 'Non', manual: 'Dimensions saisies manuellement ; aucun modèle du catalogue identifié avec certitude.', catalogNotice: 'Le lien du fabricant sert de référence au modèle. Le calcul utilise les dimensions enregistrées ci-dessous, qui peuvent différer du catalogue. Les dimensions du catalogue excluent l’emballage. Vérifiez les dimensions réelles, poignées, emballage et matériel de transport compris, ainsi que la position de transport autorisée.', upright: 'Debout', 'upright-sideways': 'Debout, tourné latéralement', 'stair-tilt': 'Incliné selon la pente de l’escalier', 'stair-tilt-sideways': 'Tourné latéralement et incliné selon la pente' },
  es: { title: 'Estimación del transporte', model: 'Modelo / objeto', recorded: 'Datos guardados (UTC)', recalculated: 'Recalculado al exportar el informe a partir de los datos guardados. Es una comprobación conservadora de volúmenes, no una confirmación de una ruta sin colisiones ni de un transporte seguro.', inputs: 'Datos utilizados', scenario: 'Orientación comprobada', startingYaw: 'Giro inicial', tilt: 'Inclinación', stairAngle: 'Pendiente de la escalera', clearances: 'Holguras restantes de la orientación elegida', clearance: 'Holgura restante (m)', reasons: 'Motivos', assumptions: 'Supuestos y límites', yes: 'Sí', no: 'No', manual: 'Medidas introducidas manualmente; sin coincidencia inequívoca en el catálogo.', catalogNotice: 'El enlace del fabricante es una referencia del modelo. El cálculo usa las medidas guardadas que se muestran abajo, que pueden diferir del catálogo. Las medidas del catálogo excluyen el embalaje. Comprueba las dimensiones reales con tiradores, embalaje y medios de transporte, y la posición de transporte permitida.', upright: 'Vertical', 'upright-sideways': 'Vertical, girado lateralmente', 'stair-tilt': 'Inclinado según la pendiente de la escalera', 'stair-tilt-sideways': 'Girado lateralmente e inclinado según la pendiente' },
  it: { title: 'Stima del trasporto', model: 'Modello / oggetto', recorded: 'Dati salvati (UTC)', recalculated: 'Ricalcolato durante l’esportazione del rapporto usando i dati salvati. È una verifica conservativa degli ingombri, non una conferma di un percorso privo di collisioni o di un trasporto sicuro.', inputs: 'Dati utilizzati', scenario: 'Orientamento verificato', startingYaw: 'Rotazione iniziale', tilt: 'Inclinazione', stairAngle: 'Pendenza della scala', clearances: 'Spazi residui per l’orientamento scelto', clearance: 'Spazio residuo (m)', reasons: 'Motivi', assumptions: 'Ipotesi e limiti', yes: 'Sì', no: 'No', manual: 'Misure inserite manualmente; nessuna corrispondenza univoca nel catalogo.', catalogNotice: 'Il collegamento del produttore è un riferimento al modello. Il calcolo usa le misure salvate riportate sotto, che possono differire dal catalogo. Le misure del catalogo escludono l’imballaggio. Verifica le dimensioni reali con maniglie, imballaggio e attrezzature, oltre alla posizione di trasporto consentita.', upright: 'Verticale', 'upright-sideways': 'Verticale, ruotato lateralmente', 'stair-tilt': 'Inclinato secondo la pendenza della scala', 'stair-tilt-sideways': 'Ruotato lateralmente e inclinato secondo la pendenza' },
  'zh-Hans': { title: '搬运空间估算', model: '型号 / 物件', recorded: '保存的输入时间（UTC）', recalculated: '导出报告时根据已保存的输入重新计算。这是保守的包络空间检查，不代表已确认路线无碰撞或搬运安全。', inputs: '使用的输入数据', scenario: '已检查姿态', startingYaw: '初始旋转角度', tilt: '倾斜角度', stairAngle: '楼梯坡度', clearances: '所选姿态的剩余净空', clearance: '剩余净空（米）', reasons: '原因', assumptions: '假设与限制', yes: '是', no: '否', manual: '手动输入的尺寸；未能唯一匹配目录型号。', catalogNotice: '制造商链接用于参考型号。计算使用下方保存的尺寸，可能与目录尺寸不同。目录尺寸不含包装。请核对包括把手、包装、搬运工具在内的实物外部尺寸，以及制造商允许的搬运姿态。', upright: '直立', 'upright-sideways': '直立并侧向旋转', 'stair-tilt': '按楼梯坡度倾斜', 'stair-tilt-sideways': '侧向旋转并按楼梯坡度倾斜' }
};
const assumptionKeys = ['rectangular_object', 'unobstructed_rectangular_passage', 'centred_turn_on_rectangular_landing', 'tilt_transitions_fit_landing', 'no_step_or_handrail_collision_test', 'no_carriers_or_equipment', 'verify_actual_route_and_manufacturer_transport_instructions'];
const assumptionLabels = {
  de: ['Der Gegenstand wird als rechteckiger Quader angenähert.', 'Der Durchgang wird als frei und rechteckig angenommen.', 'Die Drehung erfolgt mittig auf einem rechteckigen Podest; versetzte Wege werden nicht geplant.', 'Falls gekippt wird, muss auch das Aufrichten und Absenken in den geprüften Podest-Hüllraum passen.', 'Kollisionen mit einzelnen Stufen und Geländern werden nicht geprüft.', 'Träger und Transporthilfen sind nicht als eigene Körper modelliert.', 'Den vollständigen Weg am Objekt sowie die Transportvorgaben des Herstellers prüfen.'],
  fr: ['L’objet est représenté par un parallélépipède rectangle.', 'Le passage est supposé rectangulaire et sans obstacle.', 'La rotation est centrée sur un palier rectangulaire ; les trajectoires décentrées ne sont pas calculées.', 'En cas d’inclinaison, le redressement et l’abaissement doivent aussi tenir dans l’enveloppe vérifiée du palier.', 'Les collisions avec les marches individuelles et les rampes ne sont pas vérifiées.', 'Les porteurs et le matériel de manutention ne sont pas modélisés comme des corps distincts.', 'Vérifiez le trajet complet sur place et les instructions de transport du fabricant.'],
  es: ['El objeto se aproxima mediante un prisma rectangular.', 'Se supone un paso rectangular y libre de obstáculos.', 'El giro está centrado en un rellano rectangular; no se planifican rutas desplazadas.', 'Si se inclina, el proceso de levantarlo y bajarlo también debe caber en el volumen comprobado del rellano.', 'No se comprueban colisiones con escalones individuales ni barandillas.', 'Las personas y los equipos de transporte no se modelan como cuerpos independientes.', 'Comprueba la ruta completa in situ y las instrucciones de transporte del fabricante.'],
  it: ['L’oggetto è approssimato con un parallelepipedo rettangolo.', 'Il passaggio è considerato rettangolare e privo di ostacoli.', 'La rotazione è centrata su un pianerottolo rettangolare; non vengono pianificati percorsi decentrati.', 'Se si inclina l’oggetto, anche il sollevamento e l’abbassamento devono rientrare nell’ingombro verificato del pianerottolo.', 'Non vengono controllate collisioni con singoli gradini o ringhiere.', 'Le persone e le attrezzature di trasporto non sono modellate come corpi separati.', 'Verifica l’intero percorso sul posto e le istruzioni di trasporto del produttore.'],
  'zh-Hans': ['物件近似为长方体。', '假设通道为无障碍的矩形空间。', '假设在矩形平台中央转弯；不会规划偏移路线。', '如果倾斜搬运，竖起和放下的整个过程也必须容纳在已检查的平台包络中。', '不检查与单个台阶或扶手的碰撞。', '搬运人员及设备没有作为独立物体建模。', '请现场核对完整路线，并遵守制造商的搬运说明。']
};
function transportReport(record, locale, format) {
  if (!record || typeof record.model !== 'string' || record.model.length > 200 || typeof record.assessedAt !== 'string' || !Number.isFinite(Date.parse(record.assessedAt))) throw new MeasureError('invalidTransport');
  const result = assessTransport(record.input), words = transportLabels[locale];
  const label = key => escapeHTML(words[key] || experienceText(locale, key));
  const ui = key => escapeHTML(experienceText(locale, key));
  const normalize = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/gi, '').toLowerCase();
  const modelKey = normalize(record.model);
  const reference = modelKey ? applianceCatalog.find(item => modelKey === normalize(item.model) || modelKey === normalize(`${item.brand} ${item.model}`)) : undefined;
  let source = `<p class="muted">${label('manual')}</p>`;
  if (reference) {
    const url = new URL(reference.sourceUrl);
    if (url.protocol === 'https:' && !url.username && !url.password) source = `<p>${ui('catalogSource')}: <a href="${escapeHTML(url.href)}" target="_blank" rel="noopener noreferrer">${escapeHTML(`${reference.brand} ${reference.model}`)}</a> · ${escapeHTML(reference.verifiedAt)}</p><p class="muted">${label('catalogNotice')}</p>`;
  }
  const fields = [['objectWidth', record.input.object.width, 'm'], ['objectDepth', record.input.object.depth, 'm'], ['objectHeight', record.input.object.height, 'm'], ['routeWidth', record.input.route.width, 'm'], ['routeCeiling', record.input.route.ceiling, 'm'], ['landingWidth', record.input.route.landingWidth, 'm'], ['landingDepth', record.input.route.landingDepth, 'm'], ['stairRise', record.input.route.rise, 'm'], ['stairRun', record.input.route.run, 'm'], ['turnAngle', record.input.route.turnDegrees, '°'], ['margin', result.marginPerSide, 'm']];
  const inputRows = fields.map(([key, value, unit]) => `<tr><th scope="row">${ui(key)}</th><td class="number">${format(value)} ${unit}</td></tr>`).join('');
  const chosen = result.scenarios.find(scenario => scenario.id === result.chosenScenario);
  const signed = value => `${value > 0 ? '+' : ''}${format(value)}`;
  const clearanceLabels = { corridorWidth: 'routeWidth', ceiling: 'routeCeiling', landingWidth: 'landingWidth', landingDepth: 'landingDepth' };
  const clearanceRows = Object.entries(result.limitingClearances).map(([key, value]) => `<tr><th scope="row">${ui(clearanceLabels[key])}</th><td class="number${value < 0 ? ' negative' : ''}">${signed(value)} m</td></tr>`).join('');
  const assumptions = result.assumptions.map(key => `<li>${escapeHTML(assumptionLabels[locale][assumptionKeys.indexOf(key)] || key)}</li>`).join('');
  const date = new Date(record.assessedAt);
  return `<section class="transport-report"><h2>${label('title')}</h2><p class="transport-verdict ${result.verdict}">${ui(result.verdict)}</p><p class="notice">${label('recalculated')}</p><dl><dt>${label('model')}</dt><dd>${escapeHTML(record.model || experienceText(locale, 'manualDimensions'))}</dd><dt>${label('recorded')}</dt><dd><time datetime="${date.toISOString()}">${escapeHTML(new Intl.DateTimeFormat(locale, { dateStyle: 'long', timeStyle: 'short', timeZone: 'UTC' }).format(date))}</time></dd><dt>${label('scenario')}</dt><dd>${label(result.chosenScenario)}</dd><dt>${label('startingYaw')}</dt><dd>${format(result.startingYaw)}°</dd><dt>${label('tilt')}</dt><dd>${format(chosen.tilt)}°</dd><dt>${label('stairAngle')}</dt><dd>${format(result.stairAngle)}°</dd><dt>${ui('allowTilt')}</dt><dd>${label(record.input.allowTilt ? 'yes' : 'no')}</dd></dl>${source}<h3>${label('inputs')}</h3><table class="transport-table"><tbody>${inputRows}</tbody></table><h3>${label('clearances')}</h3><table class="transport-table"><thead><tr><th>${label('inputs')}</th><th>${label('clearance')}</th></tr></thead><tbody>${clearanceRows}</tbody></table><h3>${label('reasons')}</h3><ul>${result.reasons.map(reason => `<li>${ui(reason)}</li>`).join('')}</ul><h3>${label('assumptions')}</h3><ul>${assumptions}</ul></section>`;
}

function reportPhotos(photoData) {
  if (!photoData || typeof photoData !== 'object' || Array.isArray(photoData)) throw new MeasureError('invalidProject');
  let total = 0;
  const verified = new Map();
  for (const [path, data] of Object.entries(photoData)) {
    if (typeof data !== 'string' || !/^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(data)) throw new MeasureError('invalidProject');
    const body = data.slice(data.indexOf(',') + 1);
    if (body.length % 4 !== 0) throw new MeasureError('invalidProject');
    const bytes = body.length / 4 * 3 - (body.endsWith('==') ? 2 : body.endsWith('=') ? 1 : 0);
    total += bytes;
    if (bytes > 5 * 1024 * 1024 || total > 25 * 1024 * 1024) throw new MeasureError('tooLarge');
    verified.set(path, data);
  }
  return verified;
}

/** Self-contained HTML with an A4 print stylesheet and a Print/PDF button.
 * No PDF is generated automatically: the browser print dialog saves the PDF.
 * photoData maps stored note-photo paths to JPEG/PNG/WebP data URLs; no URLs load.
 */
export function measurementReport(project, { language = 'de', dictionary = {}, createdAt = new Date(), photoData = {} } = {}) {
  validateProject(project);
  const locale = reportLanguage(language), defaults = labels[locale];
  const t = key => typeof dictionary?.[key] === 'string' && dictionary[key] ? dictionary[key] : defaults[key] || key;
  const text = key => escapeHTML(t(key));
  const format = value => new Intl.NumberFormat(locale, { minimumFractionDigits: 3, maximumFractionDigits: 3 }).format(value);
  const signed = value => `${value > 0 ? '+' : ''}${format(value)}`;
  const valueCell = (value, unit) => value === undefined ? '<td class="number">—</td>' : `<td class="number">${format(value)}<span class="unit"> ${unit}</span></td>`;
  const date = createdAt instanceof Date ? createdAt : new Date(createdAt);
  if (!Number.isFinite(date.getTime())) throw new MeasureError('invalidProject');
  const photos = reportPhotos(photoData);
  const rows = project.measurements.map(measurement => {
    const result = resultFor(measurement, project.scale);
    return `<tr><th scope="row">${escapeHTML(measurement.label)}</th><td>${text(measurement.kind)}</td>${valueCell(result.length, 'm')}${valueCell(result.horizontal, 'm')}${valueCell(result.vertical, 'm')}${valueCell(result.area, 'm²')}${valueCell(result.perimeter, 'm')}</tr>`;
  }).join('');
  let plan = '';
  if (project.measurements.some(measurement => measurement.kind === 'floor')) {
    const svg = floorplanSVG(project.measurements, project.scale, project.name).replace('KANTURA · floor contours · m · verify against a reference', text('floorNote'));
    plan = `<section class="plan"><h2>${text('floorplan')}</h2><figure>${svg}<figcaption>${text('planNote')}</figcaption></figure></section>`;
  }
  const checks = project.checks || [];
  if (!Array.isArray(checks) || checks.length > 500) throw new MeasureError('invalidProject');
  const checkRows = checks.map(check => {
    if (!check || typeof check.label !== 'string' || check.label.length > 200 || !Array.isArray(check.points) || check.points.length !== 2 || !Number.isFinite(check.knownMeters) || check.knownMeters <= 0) throw new MeasureError('invalidProject');
    const measured = distance(check.points[0], check.points[1], project.scale).length, difference = measured - check.knownMeters;
    return `<tr><th scope="row">${escapeHTML(check.label)}</th>${valueCell(check.knownMeters, 'm')}${valueCell(measured, 'm')}<td class="number">${signed(difference)} m</td><td class="number">${signed(difference / check.knownMeters * 100)} %</td></tr>`;
  }).join('');
  const checkSection = checkRows ? `<section><h2>${text('checks')}</h2><table><thead><tr><th>${text('name')}</th><th>${text('known')}</th><th>${text('measured')}</th><th>${text('deviation')}</th><th>${text('relative')}</th></tr></thead><tbody>${checkRows}</tbody></table></section>` : '';
  const notes = project.notes || [];
  if (!Array.isArray(notes) || notes.length > 500) throw new MeasureError('invalidProject');
  const noteCards = notes.map(note => {
    if (!note || typeof note.title !== 'string' || note.title.length > 200 || typeof note.description !== 'string' || note.description.length > 10000 || !['door', 'window', 'gate', 'wall', 'other'].includes(note.kind)) throw new MeasureError('invalidProject');
    validatePoints([note.point], 1);
    const photo = photos.get(note.photo);
    return `<article class="note"><h3>${escapeHTML(note.title)}</h3><p class="kind">${text(note.kind)}</p><p class="description">${escapeHTML(note.description)}</p><p class="coordinates">${text('position')}: X ${format(note.point[0] * project.scale)} · Y ${format(note.point[1] * project.scale)} · Z ${format(note.point[2] * project.scale)}</p>${photo ? `<img src="${escapeHTML(photo)}" alt="${escapeHTML(note.title)}">` : note.photo ? `<p class="muted">${text('noPhoto')}</p>` : ''}</article>`;
  }).join('');
  const noteSection = noteCards ? `<section><h2>${text('notes')}</h2><div class="notes">${noteCards}</div></section>` : '';
  const transport = project.transport === undefined ? '' : transportReport(project.transport, locale, format);
  return `<!doctype html>
<html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"><title>${escapeHTML(project.name)} · ${text('report')} · KANTURA</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#eef0f3;color:#202832;font:14px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}main{max-width:1040px;margin:28px auto;padding:40px;background:white;border-radius:14px}header{border-bottom:3px solid #1f5e60;padding-bottom:24px}.brand{font-size:12px;letter-spacing:.2em;font-weight:800;color:#1f5e60}h1{font-size:30px;line-height:1.2;margin:10px 0 8px;overflow-wrap:anywhere}h2{font-size:20px;margin:28px 0 12px}h3{font-size:16px;margin:0 0 5px}p{margin:7px 0}dl{display:grid;grid-template-columns:180px 1fr;gap:5px 18px;margin:18px 0 0}dt{color:#54616d}dd{margin:0;overflow-wrap:anywhere}button{border:0;border-radius:9px;padding:12px 18px;background:#1f5e60;color:white;font:inherit;cursor:pointer}.toolbar{max-width:1040px;margin:24px auto 0;display:flex;align-items:center;gap:18px;padding:0 12px}.toolbar p{color:#54616d;font-size:13px}.status{font-weight:650}.notice{border-left:3px solid #e4b453;padding:10px 16px;background:#fff8e8;margin-top:22px;font-size:12px}table{border-collapse:collapse;width:100%;table-layout:fixed;font-size:12px}thead{display:table-header-group}th,td{text-align:left;vertical-align:top;padding:10px 7px;border-bottom:1px solid #dce2e6;overflow-wrap:anywhere}thead th{background:#f0f5f5;color:#264b4c}tbody th{font-weight:550}th:first-child{width:21%}.number{text-align:right;font-variant-numeric:tabular-nums}.unit{white-space:nowrap;color:#58636e}figure{margin:0}figure svg{width:100%;max-height:600px;height:auto}figcaption,.muted{font-size:12px;color:#596671}.notes{display:grid;grid-template-columns:1fr 1fr;gap:18px}.note{border:1px solid #dce2e6;border-radius:8px;padding:16px;break-inside:avoid;overflow-wrap:anywhere}.kind,.coordinates{font-size:11px;color:#52636c}.description{white-space:pre-wrap}.note img{display:block;width:100%;max-height:260px;object-fit:contain;margin-top:10px}footer{font-size:11px;color:#68747c;border-top:1px solid #dce2e6;padding-top:15px;margin-top:30px}.plan{break-inside:avoid}@page{size:A4 portrait;margin:14mm}@media print{body{background:white;font-size:10pt}main{margin:0;padding:0;max-width:none;border-radius:0}.toolbar{display:none}h1{font-size:23pt}h2{font-size:14pt;break-after:avoid}h3{font-size:11pt}header{padding-bottom:12px}table{font-size:8pt}th,td{padding:6px 4px}tr{break-inside:avoid}dl{grid-template-columns:42mm 1fr}.notice{font-size:8pt}figure svg{max-height:150mm}.note img{max-height:65mm}.notes{gap:4mm}footer{font-size:8pt}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}}@media(max-width:650px){main{margin:12px;padding:20px}.toolbar{align-items:flex-start;flex-direction:column;gap:4px}.notes{grid-template-columns:1fr}dl{grid-template-columns:1fr;gap:2px}dd{margin-bottom:7px}table{font-size:10px}th,td{padding:7px 3px}}
.transport-report h3{margin:18px 0 8px;break-after:avoid}.transport-report ul{padding-left:20px;font-size:12px}.transport-report li{margin:5px 0}.transport-table th:first-child{width:65%}.transport-verdict{font-size:16px;font-weight:700;border-left:4px solid #8b712d;padding:10px 14px;background:#faf5e8}.transport-verdict.possible{border-color:#376a57;background:#eff7f2}.transport-verdict.blocked{border-color:#a04436;background:#fff1ed}.negative{color:#963e32}a{color:#1f5e60;overflow-wrap:anywhere}@media print{.transport-report{break-before:page}.transport-report ul{font-size:8pt}.transport-verdict{font-size:12pt}}
</style></head><body><div class="toolbar"><button type="button" id="print-report">${text('print')}</button><p>${text('pdfHint')}</p></div><main>
<header><div class="brand">KANTURA · SCAN &amp; MEASURE</div><h1>${escapeHTML(project.name)}</h1><p>${text('report')}</p><dl><dt>${text('date')}</dt><dd><time datetime="${date.toISOString()}">${escapeHTML(new Intl.DateTimeFormat(locale, { dateStyle: 'long', timeStyle: 'short', timeZone: 'UTC' }).format(date))}</time></dd><dt>${text('reference')}</dt><dd class="status">${text(project.calibrated === true ? 'calibrated' : 'unverified')}</dd><dt>${text('scale')}</dt><dd>${escapeHTML(new Intl.NumberFormat(locale, { maximumSignificantDigits: 12 }).format(project.scale))} m</dd></dl></header>
<p class="notice">${text('note')}</p><section><h2>${text('measurements')}</h2>${rows ? `<table><thead><tr><th>${text('name')}</th><th>${text('type')}</th><th>${text('length')}</th><th>${text('horizontal')}</th><th>${text('vertical')}</th><th>${text('area')}</th><th>${text('perimeter')}</th></tr></thead><tbody>${rows}</tbody></table>` : `<p>${text('empty')}</p>`}</section>${checkSection}${plan}${noteSection}${transport}<footer>KANTURA · ${text('report')} · ${escapeHTML(project.name)}</footer></main><script>document.getElementById('print-report').addEventListener('click',function(){window.print();});</script></body></html>`;
}
