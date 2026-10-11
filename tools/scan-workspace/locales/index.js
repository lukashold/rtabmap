// Shared complete packs for the additional native/browser languages.
import pt from './pt.json' with { type: 'json' };
import ar from './ar.json' with { type: 'json' };
import hi from './hi.json' with { type: 'json' };
import bn from './bn.json' with { type: 'json' };
import ru from './ru.json' with { type: 'json' };
import ja from './ja.json' with { type: 'json' };
import ko from './ko.json' with { type: 'json' };
import id from './id.json' with { type: 'json' };
import tr from './tr.json' with { type: 'json' };

export const extraLocales = { pt, ar, hi, bn, ru, ja, ko, id, tr };
export const supportedLanguages = ['de', 'en', 'fr', 'es', 'it', 'zh-Hans', 'pt', 'ar', 'hi', 'bn', 'ru', 'ja', 'ko', 'id', 'tr'];
export const directionFor = language => String(language).toLowerCase().split(/[-_]/)[0] === 'ar' ? 'rtl' : 'ltr';
