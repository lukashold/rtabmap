// Small verified OFFLINE catalogue, not a live model-number lookup service.
// Values are manufacturer-listed unpacked dimensions in metres. Accessories,
// handles, packaging and permissible transport positions must be checked onsite.
export const applianceCatalog = [
  {
    model: 'KGN39VLEA', brand: 'Bosch', width: 0.600, depth: 0.660, height: 2.030,
    sourceUrl: 'https://www.bosch-home.com/de/de/product/KGN39VLEA',
    sourceLabel: 'Bosch Deutschland · Abmessungen des Gerätes (H × B × T): 2030 × 600 × 660 mm',
    additionalSourceUrl: 'https://media3.bosch-home.com/Documents/eudatasheet/de-DE/KGN39VLEA.pdf',
    verifiedAt: '2026-10-11', dimensionUnit: 'm', dimensionBasis: 'unpacked',
    note: 'Hersteller-Gerätemaße. Bosch führt das Modell als nicht mehr verfügbar; der Eintrag dient dem Maßvergleich vorhandener Geräte.'
  },
  {
    model: 'RB34C600ESA/EF', brand: 'Samsung', width: 0.595, depth: 0.658, height: 1.853,
    sourceUrl: 'https://www.samsung.com/at/refrigerators/bottom-mount-freezer/rb7300t-344l-silver-rb34c600esa-ef/',
    sourceLabel: 'Samsung Österreich · Nettobreite 595 mm, Höhe mit Gelenk 1853 mm, Tiefe ohne Türgriff 658 mm',
    verifiedAt: '2026-10-11', dimensionUnit: 'm', dimensionBasis: 'unpacked-excluding-handle',
    note: 'Die angegebene Tiefe schließt laut Hersteller den Türgriff aus. Für den Transport die tatsächliche größte Tiefe einschließlich aller Anbauteile messen.'
  },
  {
    model: 'GBP62PZNAC', brand: 'LG', width: 0.595, depth: 0.675, height: 2.030,
    sourceUrl: 'https://www.lg.com/at/kuhlschranke/kuhl-gefrierkombinationen/gbp62pznac/',
    sourceLabel: 'LG Österreich · Abmessungen & Gewicht, B × H × T: 595 × 2030 × 675 mm',
    verifiedAt: '2026-10-11', dimensionUnit: 'm', dimensionBasis: 'unpacked',
    packagedDimensions: { width: 0.634, depth: 0.745, height: 2.135 },
    note: 'Unverpackte Gerätemaße. Die Herstellerangabe mit Verpackung beträgt 634 × 2135 × 745 mm (B × H × T).'
  }
].map(item => Object.freeze(item));
Object.freeze(applianceCatalog);

const normalize = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/gi, '').toLowerCase();
export function searchAppliances(query = '') {
  if (typeof query !== 'string' || query.length > 120) return [];
  const needle = normalize(query);
  return applianceCatalog.filter(item => normalize(`${item.brand} ${item.model}`).includes(needle) || normalize(item.model).includes(needle));
}
