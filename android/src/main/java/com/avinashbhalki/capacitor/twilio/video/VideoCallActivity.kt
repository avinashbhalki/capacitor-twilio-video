package com.avinashbhalki.capacitor.twilio.video

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import androidx.appcompat.app.AppCompatActivity
import com.twilio.video.*
import tvi.webrtc.VideoSink

class VideoCallActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "VideoCallActivity"
        private var instance: VideoCallActivity? = null

        fun getInstance(): VideoCallActivity? {
            return instance
        }
    }

    // Call State Machine
    enum class CallState {
        IDLE,            // No active call
        JOINING,         // joinRoom invoked, not yet connected
        CONNECTED,       // Room connected
        DISCONNECTING,   // leaveRoom or auto-close in progress
        DISCONNECTED     // Call fully ended
    }

    // UI Elements
    private lateinit var primaryVideoView: VideoView
    private lateinit var thumbnailVideoView: VideoView
    private lateinit var controlsContainer: FrameLayout
    private lateinit var muteButton: ImageButton
    private lateinit var videoButton: ImageButton
    private lateinit var flipButton: ImageButton
    private lateinit var speakerButton: ImageButton
    private lateinit var hangupButton: ImageButton

    // Twilio Video
    private var room: Room? = null
    private var localParticipant: LocalParticipant? = null
    private var localVideoTrack: LocalVideoTrack? = null
    private var localAudioTrack: LocalAudioTrack? = null
    private var cameraCapturer: CameraCapturer? = null
    private var audioManager: AudioManager? = null

    // State
    private var callState: CallState = CallState.IDLE
    private var isAudioMuted = false
    private var isVideoEnabled = true
    private var isSpeakerEnabled = true
    private var accessToken: String? = null
    private var roomName: String? = null
    private var remoteParticipantCount = 0

    // Multi-participant video management
    private val participantVideoViews = mutableMapOf<String, VideoView>()
    private var dominantSpeakerIdentity: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var dominantSpeakerDebounceRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        // Create full-screen layout
        createFullScreenLayout()

        accessToken = intent.getStringExtra("token")
        roomName = intent.getStringExtra("roomName")

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        setupLocalMedia()

        // Transition to JOINING state
        transitionToState(CallState.JOINING)
        connectToRoom()
    }

    private fun createFullScreenLayout() {
        val rootLayout = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(android.graphics.Color.BLACK)
        }

        // Primary video view (remote participant - full screen)
        primaryVideoView = VideoView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        rootLayout.addView(primaryVideoView)

        // Thumbnail video view (local participant - picture-in-picture)
        thumbnailVideoView = VideoView(this).apply {
            val size = (120 * resources.displayMetrics.density).toInt()
            layoutParams = FrameLayout.LayoutParams(size, size).apply {
                setMargins(16, 16, 16, 16)
                gravity = android.view.Gravity.TOP or android.view.Gravity.END
            }
            setBackgroundColor(android.graphics.Color.DKGRAY)
        }
        rootLayout.addView(thumbnailVideoView)

        // Controls container at bottom
        controlsContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                (80 * resources.displayMetrics.density).toInt()
            ).apply {
                gravity = android.view.Gravity.BOTTOM
            }
            setBackgroundColor(android.graphics.Color.parseColor("#AA000000"))
            setPadding(16, 16, 16, 16)
        }

        // Create controls layout
        val controlsLayout = android.widget.LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER
        }

        muteButton = createControlButton("🎤")
        videoButton = createControlButton("📹")
        flipButton = createControlButton("🔄")
        speakerButton = createControlButton("🔊")
        hangupButton = createControlButton("📞").apply {
            setBackgroundColor(android.graphics.Color.RED)
        }

        controlsLayout.addView(muteButton)
        controlsLayout.addView(videoButton)
        controlsLayout.addView(flipButton)
        controlsLayout.addView(speakerButton)
        controlsLayout.addView(hangupButton)

        controlsContainer.addView(controlsLayout)
        rootLayout.addView(controlsContainer)

        setContentView(rootLayout)

        // Set button listeners
        muteButton.setOnClickListener { toggleAudioMute() }
        videoButton.setOnClickListener { toggleVideo() }
        flipButton.setOnClickListener { flipCamera() }
        speakerButton.setOnClickListener { toggleSpeaker() }
        hangupButton.setOnClickListener { disconnect() }
    }

    private fun createControlButton(text: String): ImageButton {
        return ImageButton(this).apply {
            val size = (48 * resources.displayMetrics.density).toInt()
            val margin = (8 * resources.displayMetrics.density).toInt()
            layoutParams = android.widget.LinearLayout.LayoutParams(size, size).apply {
                setMargins(margin, 0, margin, 0)
            }
            contentDescription = text

            // Set up stateful background
            backgroundTintList = createButtonColorStateList()
            isClickable = true
            isFocusable = true
        }
    }

    private fun createButtonColorStateList(): ColorStateList {
        val states = arrayOf(
            intArrayOf(-android.R.attr.state_enabled), // Disabled
            intArrayOf(android.R.attr.state_selected),   // Selected/Active
            intArrayOf()                                  // Default
        )

        val colors = intArrayOf(
            Color.parseColor("#444444"),  // Disabled - dark gray
            Color.parseColor("#4CAF50"),  // Selected - green
            Color.parseColor("#888888")   // Default - gray
        )

        return ColorStateList(states, colors)
    }

    private fun setupLocalMedia() {
        // Create local audio track
        localAudioTrack = LocalAudioTrack.create(this, true, "local_audio")

        // Create camera capturer
        val cameraSource = CameraSource.FRONT_CAMERA
        cameraCapturer = CameraCapturer(this, cameraSource)

        // Create local video track
        localVideoTrack = LocalVideoTrack.create(this, true, cameraCapturer!!, "local_video")
        localVideoTrack?.addSink(thumbnailVideoView)
    }

    private fun connectToRoom() {
        val connectOptions = ConnectOptions.Builder(accessToken!!)
            .roomName(roomName)
            .audioTracks(listOfNotNull(localAudioTrack))
            .videoTracks(listOfNotNull(localVideoTrack))
            .enableNetworkQuality(true)
            .enableDominantSpeaker(true)
            .networkQualityConfiguration(
                NetworkQualityConfiguration(
                    NetworkQualityVerbosity.NETWORK_QUALITY_VERBOSITY_MINIMAL,
                    NetworkQualityVerbosity.NETWORK_QUALITY_VERBOSITY_MINIMAL
                )
            )
            .roomListener(roomListener)
            .build()

        room = Video.connect(this, connectOptions)
    }

    private val roomListener = object : Room.Listener {
        override fun onConnected(room: Room) {
            Log.d(TAG, "Connected to room: ${room.name}")
            localParticipant = room.localParticipant

            // Transition to CONNECTED state
            transitionToState(CallState.CONNECTED)

            TwilioVideoPlugin.getInstance()?.notifyRoomConnected(room.name)

            // Handle existing participants
            room.remoteParticipants.forEach { participant ->
                addRemoteParticipant(participant)
            }

            // Update UI to reflect connected state
            updateButtonStates()
        }

        override fun onReconnecting(room: Room, twilioException: TwilioException) {
            Log.d(TAG, "Reconnecting to room: ${room.name}")
        }

        override fun onReconnected(room: Room) {
            Log.d(TAG, "Reconnected to room: ${room.name}")
        }

        override fun onConnectFailure(room: Room, twilioException: TwilioException) {
            Log.e(TAG, "Connect failure: ${twilioException.message}")

            // Transition to DISCONNECTED on failure
            transitionToState(CallState.DISCONNECTED)

            TwilioVideoPlugin.getInstance()?.notifyRoomError(
                twilioException.code.toString(),
                twilioException.message ?: "Connection failed",
                true
            )
            finish()
        }

        override fun onDisconnected(room: Room, twilioException: TwilioException?) {
            Log.d(TAG, "Disconnected from room: ${room.name}")

            // Transition to DISCONNECTED
            transitionToState(CallState.DISCONNECTED)

            TwilioVideoPlugin.getInstance()?.notifyRoomDisconnected(
                room.name,
                twilioException?.message
            )
            cleanup()
            finish()
        }

        override fun onParticipantConnected(room: Room, participant: RemoteParticipant) {
            Log.d(TAG, "Participant connected: ${participant.identity}")
            addRemoteParticipant(participant)
            TwilioVideoPlugin.getInstance()?.notifyParticipantJoined(participant.identity)
        }

        override fun onParticipantDisconnected(room: Room, participant: RemoteParticipant) {
            Log.d(TAG, "Participant disconnected: ${participant.identity}")
            removeRemoteParticipant(participant)
            TwilioVideoPlugin.getInstance()?.notifyParticipantLeft(participant.identity)

            // Auto-close logic: if no remote participants remain
            checkAutoClose()
        }

        override fun onRecordingStarted(room: Room) {}
        override fun onRecordingStopped(room: Room) {}

        override fun onDominantSpeakerChanged(room: Room, remoteParticipant: RemoteParticipant?) {
            Log.d(TAG, "Dominant speaker: ${remoteParticipant?.identity}")

            // Debounce dominant speaker changes to avoid flicker
            dominantSpeakerDebounceRunnable?.let { mainHandler.removeCallbacks(it) }

            dominantSpeakerDebounceRunnable = Runnable {
                updateDominantSpeaker(remoteParticipant?.identity)
            }

            mainHandler.postDelayed(dominantSpeakerDebounceRunnable!!, 300)

            TwilioVideoPlugin.getInstance()?.notifyDominantSpeakerChanged(remoteParticipant?.identity)
        }
    }

    private fun addRemoteParticipant(participant: RemoteParticipant) {
        remoteParticipantCount++
        participant.setListener(remoteParticipantListener)

        // Create or get stable video view for this participant
        val videoView = participantVideoViews.getOrPut(participant.identity) {
            VideoView(this).apply {
                Log.d(TAG, "Created new VideoView for participant: ${participant.identity}")
            }
        }

        participant.remoteVideoTracks.forEach { publication ->
            if (publication.isTrackSubscribed) {
                publication.remoteVideoTrack?.let { track ->
                    addRemoteVideoTrack(participant.identity, track)
                }
            }
        }
    }

    private fun removeRemoteParticipant(participant: RemoteParticipant) {
        remoteParticipantCount--

        participant.remoteVideoTracks.forEach { publication ->
            if (publication.isTrackSubscribed) {
                publication.remoteVideoTrack?.let { track ->
                    removeRemoteVideoTrack(participant.identity, track)
                }
            }
        }

        // Clean up video view for this participant
        participantVideoViews.remove(participant.identity)?.let { videoView ->
            runOnUiThread {
                if (primaryVideoView.childCount > 0 && primaryVideoView.getChildAt(0) == videoView) {
                    primaryVideoView.removeAllViews()
                }
            }
            Log.d(TAG, "Removed VideoView for participant: ${participant.identity}")
        }
    }

    private val remoteParticipantListener = object : RemoteParticipant.Listener {
        override fun onVideoTrackPublished(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication
        ) {}

        override fun onVideoTrackUnpublished(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication
        ) {}

        override fun onVideoTrackSubscribed(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication,
            track: RemoteVideoTrack
        ) {
            Log.d(TAG, "Video track subscribed: ${participant.identity}")
            addRemoteVideoTrack(participant.identity, track)
        }

        override fun onVideoTrackUnsubscribed(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication,
            track: RemoteVideoTrack
        ) {
            Log.d(TAG, "Video track unsubscribed: ${participant.identity}")
            removeRemoteVideoTrack(participant.identity, track)
        }

        override fun onAudioTrackPublished(
            participant: RemoteParticipant,
            publication: RemoteAudioTrackPublication
        ) {}

        override fun onAudioTrackUnpublished(
            participant: RemoteParticipant,
            publication: RemoteAudioTrackPublication
        ) {}

        override fun onAudioTrackSubscribed(
            participant: RemoteParticipant,
            publication: RemoteAudioTrackPublication,
            track: RemoteAudioTrack
        ) {}

        override fun onAudioTrackUnsubscribed(
            participant: RemoteParticipant,
            publication: RemoteAudioTrackPublication,
            track: RemoteAudioTrack
        ) {}

        override fun onDataTrackPublished(
            participant: RemoteParticipant,
            publication: RemoteDataTrackPublication
        ) {}

        override fun onDataTrackUnpublished(
            participant: RemoteParticipant,
            publication: RemoteDataTrackPublication
        ) {}

        override fun onDataTrackSubscribed(
            participant: RemoteParticipant,
            publication: RemoteDataTrackPublication,
            track: RemoteDataTrack
        ) {}

        override fun onDataTrackUnsubscribed(
            participant: RemoteParticipant,
            publication: RemoteDataTrackPublication,
            track: RemoteDataTrack
        ) {}

        override fun onAudioTrackEnabled(
            participant: RemoteParticipant,
            publication: RemoteAudioTrackPublication
        ) {}

        override fun onAudioTrackDisabled(
            participant: RemoteParticipant,
            publication: RemoteAudioTrackPublication
        ) {}

        override fun onVideoTrackEnabled(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication
        ) {}

        override fun onVideoTrackDisabled(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication
        ) {}

        override fun onNetworkQualityLevelChanged(
            participant: RemoteParticipant,
            networkQualityLevel: NetworkQualityLevel
        ) {
            TwilioVideoPlugin.getInstance()?.notifyNetworkQualityChanged(
                participant.identity,
                networkQualityLevel.ordinal,
                false
            )
        }
    }

    private fun addRemoteVideoTrack(participantIdentity: String, track: RemoteVideoTrack) {
        val videoView = participantVideoViews[participantIdentity]
        if (videoView == null) {
            Log.w(TAG, "No VideoView found for participant: $participantIdentity")
            return
        }

        runOnUiThread {
            // Add sink to the stable video view (reuse, don't recreate)
            track.addSink(videoView)

            // If this is the dominant speaker or first participant, show in primary view
            if (dominantSpeakerIdentity == participantIdentity || remoteParticipantCount == 1) {
                updatePrimaryVideoView(participantIdentity)
            }

            Log.d(TAG, "Added video track sink for participant: $participantIdentity")
        }
    }

    private fun removeRemoteVideoTrack(participantIdentity: String, track: RemoteVideoTrack) {
        val videoView = participantVideoViews[participantIdentity]
        if (videoView == null) {
            Log.w(TAG, "No VideoView found for participant: $participantIdentity")
            return
        }

        runOnUiThread {
            track.removeSink(videoView)
            Log.d(TAG, "Removed video track sink for participant: $participantIdentity")
        }
    }

    private fun updateDominantSpeaker(participantIdentity: String?) {
        dominantSpeakerIdentity = participantIdentity

        if (participantIdentity != null) {
            updatePrimaryVideoView(participantIdentity)
        }
    }

    private fun updatePrimaryVideoView(participantIdentity: String) {
        val videoView = participantVideoViews[participantIdentity] ?: return

        runOnUiThread {
            // Only update if not already showing this participant
            if (primaryVideoView.childCount == 0 || primaryVideoView.getChildAt(0) != videoView) {
                primaryVideoView.removeAllViews()

                // Remove from parent if it has one
                (videoView.parent as? FrameLayout)?.removeView(videoView)

                // Add to primary view
                val layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                primaryVideoView.addView(videoView, layoutParams)

                Log.d(TAG, "Updated primary view to show participant: $participantIdentity")
            }
        }
    }

    private fun checkAutoClose() {
        if (remoteParticipantCount == 0) {
            Log.d(TAG, "All remote participants left, auto-closing")
            TwilioVideoPlugin.getInstance()?.notifyRoomAutoClosed("last-participant-left")
            disconnect()
        }
    }

    // ===== Call State Machine =====

    private fun transitionToState(newState: CallState) {
        val oldState = callState

        // Validate state transition
        val isValidTransition = when (oldState to newState) {
            CallState.IDLE to CallState.JOINING -> true
            CallState.JOINING to CallState.CONNECTED -> true
            CallState.JOINING to CallState.DISCONNECTED -> true // Failed to connect
            CallState.CONNECTED to CallState.DISCONNECTING -> true
            CallState.DISCONNECTING to CallState.DISCONNECTED -> true
            CallState.CONNECTED to CallState.DISCONNECTED -> true // Abnormal disconnect
            else -> oldState == newState // Allow same state
        }

        if (!isValidTransition) {
            Log.w(TAG, "Invalid state transition: $oldState -> $newState")
            return
        }

        Log.d(TAG, "Call state transition: $oldState -> $newState")
        callState = newState

        // Update UI based on new state
        runOnUiThread {
            updateButtonStates()
        }
    }

    private fun updateButtonStates() {
        val isConnected = callState == CallState.CONNECTED

        runOnUiThread {
            // Mute button
            muteButton.isEnabled = isConnected
            muteButton.isSelected = isAudioMuted

            // Video button
            videoButton.isEnabled = isConnected
            videoButton.isSelected = !isVideoEnabled

            // Flip button
            flipButton.isEnabled = isConnected && isVideoEnabled

            // Speaker button
            speakerButton.isEnabled = isConnected
            speakerButton.isSelected = isSpeakerEnabled

            // Hangup button - always enabled once joining
            hangupButton.isEnabled = (callState == CallState.JOINING ||
                                     callState == CallState.CONNECTED)
        }
    }

    // ===== Control Actions =====

    fun disconnect() {
        if (callState == CallState.DISCONNECTING || callState == CallState.DISCONNECTED) {
            Log.w(TAG, "Already disconnecting or disconnected, ignoring")
            return
        }

        transitionToState(CallState.DISCONNECTING)
        room?.disconnect()
        cleanup()
        runOnUiThread {
            finish()
        }
    }

    fun muteAudio(muted: Boolean) {
        if (callState != CallState.CONNECTED) {
            Log.w(TAG, "Cannot mute audio, not connected. State: $callState")
            return
        }

        isAudioMuted = muted
        localAudioTrack?.enable(!muted)
        updateButtonStates()
    }

    fun enableVideo(enabled: Boolean) {
        if (callState != CallState.CONNECTED) {
            Log.w(TAG, "Cannot toggle video, not connected. State: $callState")
            return
        }

        isVideoEnabled = enabled
        localVideoTrack?.enable(enabled)
        updateButtonStates()
    }

    fun flipCamera() {
        if (callState != CallState.CONNECTED || !isVideoEnabled) {
            Log.w(TAG, "Cannot flip camera. State: $callState, VideoEnabled: $isVideoEnabled")
            return
        }

        cameraCapturer?.switchCamera()
    }

    fun setSpeaker(enabled: Boolean) {
        if (callState != CallState.CONNECTED) {
            Log.w(TAG, "Cannot toggle speaker, not connected. State: $callState")
            return
        }

        isSpeakerEnabled = enabled
        audioManager?.let {
            it.isSpeakerphoneOn = enabled
        }
        updateButtonStates()
    }

    private fun toggleAudioMute() {
        muteAudio(!isAudioMuted)
    }

    private fun toggleVideo() {
        enableVideo(!isVideoEnabled)
    }

    private fun toggleSpeaker() {
        setSpeaker(!isSpeakerEnabled)
    }

    private fun cleanup() {
        // Cancel any pending dominant speaker updates
        dominantSpeakerDebounceRunnable?.let { mainHandler.removeCallbacks(it) }
        dominantSpeakerDebounceRunnable = null

        localVideoTrack?.let {
            it.removeSink(thumbnailVideoView)
            it.release()
        }
        localVideoTrack = null

        localAudioTrack?.release()
        localAudioTrack = null

        cameraCapturer?.stopCapture()
        cameraCapturer = null

        // Clean up all participant video views
        participantVideoViews.clear()
        dominantSpeakerIdentity = null

        room = null
        localParticipant = null
    }

    override fun onDestroy() {
        cleanup()
        instance = null

        // Reset state
        transitionToState(CallState.DISCONNECTED)

        super.onDestroy()
    }
}
