// A known reference only scales a real reconstruction. It cannot establish the
// unseen shape of an AI-generated object. Preserve this distinction on reload.
export function measurementPolicy(source, calibrated = false) {
  const generated = source === 'generated';
  return { canMeasure: !generated && (source !== 'photogrammetry' || calibrated === true),
    canCalibrate: !generated, canNote: true, metricDisplay: !generated };
}
