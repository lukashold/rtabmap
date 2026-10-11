import { readFile, writeFile } from 'node:fs/promises';
import { extraLocales, supportedLanguages } from './locales/index.js';

const guideURL = new URL('../../app/ios/RTABMapApp/MeasurementGuide.json', import.meta.url);
const videosURL = new URL('./public/videos/scripts.json', import.meta.url);
const guide = JSON.parse(await readFile(guideURL, 'utf8'));
const videos = JSON.parse(await readFile(videosURL, 'utf8'));
for (const [language, pack] of Object.entries(extraLocales)) {
  guide[language] = pack.guide;
  videos.languages[language] = pack.video;
}
const ordered = value => Object.fromEntries(supportedLanguages.map(language => [language, value[language]]));
await writeFile(guideURL, JSON.stringify(ordered(guide), null, 2) + '\n');
videos.languages = ordered(videos.languages);
await writeFile(videosURL, JSON.stringify(videos, null, 2) + '\n');
console.log(`Synchronized ${supportedLanguages.length} native guides and video scripts.`);
