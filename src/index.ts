import { registerPlugin } from '@capacitor/core';

import type { TwilioVideoPlugin } from './definitions';

const TwilioVideo = registerPlugin<TwilioVideoPlugin>('TwilioVideo', {
  web: () => import('./web').then(m => new m.TwilioVideoWeb()),
});

export * from './definitions';
export { TwilioVideo };
