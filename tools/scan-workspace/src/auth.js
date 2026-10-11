import { broadcastResponseToMainFrame } from '@azure/msal-browser/redirect-bridge';
broadcastResponseToMainFrame().catch(() => { document.querySelector('p').textContent = 'Sign-in response could not be delivered. Close this window and try again.'; });
