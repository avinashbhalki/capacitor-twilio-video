import { PluginListenerHandle } from '@capacitor/core';

/**
 * Options for joining a Twilio Video room
 */
export interface JoinRoomOptions {
  /**
   * The name of the room to join (optional if roomId is provided)
   */
  roomName?: string;

  /**
   * The unique identifier of the room (optional if roomName is provided)
   */
  roomId?: string;

  /**
   * Access token for Twilio Video authentication (required)
   */
  token: string;
}

/**
 * Options for muting/unmuting audio
 */
export interface MuteAudioOptions {
  /**
   * True to mute, false to unmute
   */
  muted: boolean;
}

/**
 * Options for enabling/disabling video
 */
export interface EnableVideoOptions {
  /**
   * True to enable, false to disable
   */
  enabled: boolean;
}

/**
 * Options for enabling/disabling speaker
 */
export interface SetSpeakerOptions {
  /**
   * True to enable speaker, false for earpiece
   */
  enabled: boolean;
}

/**
 * Event payload when room is connected
 */
export interface RoomConnectedEvent {
  /**
   * The name of the connected room
   */
  roomName: string;
}

/**
 * Event payload when room is disconnected
 */
export interface RoomDisconnectedEvent {
  /**
   * The name of the disconnected room
   */
  roomName: string;

  /**
   * Optional reason for disconnection
   */
  reason?: string;
}

/**
 * Event payload when a participant joins
 */
export interface ParticipantJoinedEvent {
  /**
   * The identity of the participant who joined
   */
  identity: string;
}

/**
 * Event payload when a participant leaves
 */
export interface ParticipantLeftEvent {
  /**
   * The identity of the participant who left
   */
  identity: string;
}

/**
 * Event payload for network quality changes
 */
export interface NetworkQualityChangedEvent {
  /**
   * The identity of the participant
   */
  identity: string;

  /**
   * Network quality level (0-5, where 5 is best)
   */
  level: number;

  /**
   * True if this is the local participant
   */
  isLocal: boolean;
}

/**
 * Event payload when dominant speaker changes
 */
export interface DominantSpeakerChangedEvent {
  /**
   * The identity of the new dominant speaker, or null if none
   */
  identity: string | null;
}

/**
 * Event payload when room is automatically closed
 */
export interface RoomAutoClosedEvent {
  /**
   * The reason for auto-closing
   */
  reason: 'last-participant-left';
}

/**
 * Event payload for room errors
 */
export interface RoomErrorEvent {
  /**
   * Error code
   */
  code: string;

  /**
   * Error message
   */
  message: string;

  /**
   * Whether this is a fatal error requiring reconnection
   */
  isFatal: boolean;
}

/**
 * Capacitor Twilio Video Plugin Interface
 */
export interface TwilioVideoPlugin {
  /**
   * Join a Twilio Video room with custom full-screen UI
   *
   * @param options - Room connection options including token and room name/id
   * @returns Promise that resolves when the room connection process starts
   *
   * @example
   * ```typescript
   * await TwilioVideo.joinRoom({
   *   roomName: 'my-room',
   *   token: 'eyJhbGc...'
   * });
   * ```
   */
  joinRoom(options: JoinRoomOptions): Promise<void>;

  /**
   * Leave the current Twilio Video room and dismiss the full-screen UI
   *
   * @returns Promise that resolves when disconnection is complete
   *
   * @example
   * ```typescript
   * await TwilioVideo.leaveRoom();
   * ```
   */
  leaveRoom(): Promise<void>;

  /**
   * Mute or unmute the local audio track
   *
   * @param options - Mute state options
   * @returns Promise that resolves when the operation completes
   *
   * @example
   * ```typescript
   * await TwilioVideo.muteAudio({ muted: true });
   * ```
   */
  muteAudio(options: MuteAudioOptions): Promise<void>;

  /**
   * Enable or disable the local video track
   *
   * @param options - Video enable state options
   * @returns Promise that resolves when the operation completes
   *
   * @example
   * ```typescript
   * await TwilioVideo.enableVideo({ enabled: false });
   * ```
   */
  enableVideo(options: EnableVideoOptions): Promise<void>;

  /**
   * Flip between front and back camera
   *
   * @returns Promise that resolves when camera flip completes
   *
   * @example
   * ```typescript
   * await TwilioVideo.flipCamera();
   * ```
   */
  flipCamera(): Promise<void>;

  /**
   * Toggle between speaker and earpiece audio output
   *
   * @param options - Speaker enable state options
   * @returns Promise that resolves when the operation completes
   *
   * @example
   * ```typescript
   * await TwilioVideo.setSpeaker({ enabled: true });
   * ```
   */
  setSpeaker(options: SetSpeakerOptions): Promise<void>;

  /**
   * Listen for room connection events
   *
   * @param eventName - 'roomConnected'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'roomConnected',
    listenerFunc: (event: RoomConnectedEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for room disconnection events
   *
   * @param eventName - 'roomDisconnected'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'roomDisconnected',
    listenerFunc: (event: RoomDisconnectedEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for participant joined events
   *
   * @param eventName - 'participantJoined'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'participantJoined',
    listenerFunc: (event: ParticipantJoinedEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for participant left events
   *
   * @param eventName - 'participantLeft'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'participantLeft',
    listenerFunc: (event: ParticipantLeftEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for network quality change events
   *
   * @param eventName - 'networkQualityChanged'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'networkQualityChanged',
    listenerFunc: (event: NetworkQualityChangedEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for dominant speaker change events
   *
   * @param eventName - 'dominantSpeakerChanged'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'dominantSpeakerChanged',
    listenerFunc: (event: DominantSpeakerChangedEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for room auto-close events
   *
   * @param eventName - 'roomAutoClosed'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'roomAutoClosed',
    listenerFunc: (event: RoomAutoClosedEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Listen for room error events
   *
   * @param eventName - 'roomError'
   * @param listenerFunc - Callback function
   * @returns Promise with PluginListenerHandle to remove the listener
   */
  addListener(
    eventName: 'roomError',
    listenerFunc: (event: RoomErrorEvent) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Remove all listeners for this plugin
   */
  removeAllListeners(): Promise<void>;
}
