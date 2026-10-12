// A known reference only scales a real reconstruction. It cannot establish the
// unseen shape of an AI-generated object. Preserve this distinction on reload.
export const captureWarningCodes = ['camera_pose_ambiguity','repeated_camera_views','insufficient_parallax'];
export function validCaptureWarnings(warnings) {
  return warnings===undefined||Array.isArray(warnings)&&warnings.length<=3&&new Set(warnings).size===warnings.length&&warnings.every(code=>captureWarningCodes.includes(code));
}
export function measurementPolicy(source, calibrated = false, warnings = []) {
  const generated = source === 'generated';
  const suspect = warnings.some(code=>['camera_pose_ambiguity','insufficient_parallax'].includes(code));
  return { canMeasure: !generated && !suspect && (source !== 'photogrammetry' || calibrated === true),
    canCalibrate: !generated && !suspect, canNote: true, metricDisplay: !generated };
}
