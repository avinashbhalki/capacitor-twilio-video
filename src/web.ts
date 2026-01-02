import { WebPlugin } from '@capacitor/core';

import type {
  JoinRoomOptions,
  MuteAudioOptions,
  EnableVideoOptions,
  SetSpeakerOptions,
} from './definitions';

export class TwilioVideoWeb extends WebPlugin {
  async joinRoom(options: JoinRoomOptions): Promise<void> {
    console.log('joinRoom', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async leaveRoom(): Promise<void> {
    throw this.unimplemented('Not implemented on web.');
  }

  async muteAudio(options: MuteAudioOptions): Promise<void> {
    console.log('muteAudio', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async enableVideo(options: EnableVideoOptions): Promise<void> {
    console.log('enableVideo', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async flipCamera(): Promise<void> {
    throw this.unimplemented('Not implemented on web.');
  }

  async setSpeaker(options: SetSpeakerOptions): Promise<void> {
    console.log('setSpeaker', options);
    throw this.unimplemented('Not implemented on web.');
  }
}
