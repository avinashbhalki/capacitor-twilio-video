package com.avinashbhalki.capacitor.twilio.video

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.ColorStateList
import android.graphics.Color
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
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

    // Audio Routing State
    enum class AudioRoute {
        BLUETOOTH,
        WIRED_HEADSET,
        SPEAKER,
        EARPIECE
    }

    // Participant Renderer - stable video view per participant
    private data class ParticipantRenderer(
        val identity: String,
        val videoView: VideoView,
        var videoTrack: RemoteVideoTrack? = null,
        var isFocused: Boolean = false
    )

    // UI Elements
    private lateinit var primaryVideoContainer: FrameLayout
    private lateinit var thumbnailGridContainer: LinearLayout
    private lateinit var localThumbnailView: VideoView
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
    private var currentAudioRoute: AudioRoute = AudioRoute.SPEAKER
    private var accessToken: String? = null
    private var roomName: String? = null
    private var remoteParticipantCount = 0

    // Participant Rendering Manager
    private val participantRenderers = mutableMapOf<String, ParticipantRenderer>()
    private var focusedParticipantIdentity: String? = null // User-selected or dominant speaker
    private var dominantSpeakerIdentity: String? = null
    private var userHasSelectedParticipant = false // User selection overrides dominant speaker
    private val mainHandler = Handler(Looper.getMainLooper())
    private var dominantSpeakerDebounceRunnable: Runnable? = null

    // Audio Management
    private var bluetoothReceiver: BroadcastReceiver? = null
    private var isBluetoothScoOn = false
    private var preferredAudioRoute: AudioRoute = AudioRoute.SPEAKER

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        // Create full-screen layout
        createFullScreenLayout()

        accessToken = intent.getStringExtra("token")
        roomName = intent.getStringExtra("roomName")

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Setup audio routing
        setupAudioRouting()

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
            setBackgroundColor(Color.BLACK)
        }

        // Primary video container (remote participant - full screen)
        primaryVideoContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.BLACK)
        }
        rootLayout.addView(primaryVideoContainer)

        // Thumbnail grid container (top-right, overlays primary video)
        val thumbnailSize = (120 * resources.displayMetrics.density).toInt()
        val thumbnailMargin = (16 * resources.displayMetrics.density).toInt()

        thumbnailGridContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                thumbnailSize,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                setMargins(thumbnailMargin, thumbnailMargin * 3, thumbnailMargin, 0)
            }
        }
        rootLayout.addView(thumbnailGridContainer)

        // Local video thumbnail (always at top of grid)
        localThumbnailView = VideoView(this).apply {
            layoutParams = LinearLayout.LayoutParams(thumbnailSize, thumbnailSize).apply {
                setMargins(0, 0, 0, thumbnailMargin / 2)
            }
            setBackgroundColor(Color.DKGRAY)
            // Make clickable to select local video as focused
            isClickable = true
            isFocusable = true
            setOnClickListener {
                onThumbnailSelected("local")
            }
        }
        thumbnailGridContainer.addView(localThumbnailView)

        // Controls container at bottom
        controlsContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                (80 * resources.displayMetrics.density).toInt()
            ).apply {
                gravity = Gravity.BOTTOM
            }
            setBackgroundColor(Color.parseColor("#AA000000"))
            setPadding(16, 16, 16, 16)
        }

        // Create controls layout
        val controlsLayout = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        muteButton = createControlButton("Mute").apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
        }
        videoButton = createControlButton("Video").apply {
            setImageResource(android.R.drawable.presence_video_online)
        }
        flipButton = createControlButton("Flip").apply {
            setImageResource(android.R.drawable.ic_menu_rotate)
        }
        speakerButton = createControlButton("Speaker").apply {
            setImageResource(android.R.drawable.ic_lock_silent_mode_off)
        }
        hangupButton = createControlButton("Hangup").apply {
            setImageResource(android.R.drawable.ic_menu_call)
            backgroundTintList = ColorStateList.valueOf(Color.RED)
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
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                setMargins(margin, 0, margin, 0)
            }
            contentDescription = text

            // Set up stateful background with proper color states
            backgroundTintList = createButtonColorStateList()
            isClickable = true
            isFocusable = true
            // Default to not selected
            isSelected = false
        }
    }

    private fun createButtonColorStateList(): ColorStateList {
        val states = arrayOf(
            intArrayOf(-android.R.attr.state_enabled), // Disabled
            intArrayOf(android.R.attr.state_selected),   // Selected/Active
            intArrayOf()                                  // Default
        )

        val colors = intArrayOf(
            Color.parseColor("#333333"),  // Disabled - dark gray
            Color.parseColor("#4CAF50"),  // Selected/Active - green
            Color.parseColor("#777777")   // Default - gray
        )

        return ColorStateList(states, colors)
    }

    // ===== Audio Routing Management =====

    private fun setupAudioRouting() {
        audioManager?.let { am ->
            // Set audio mode for communication
            am.mode = AudioManager.MODE_IN_COMMUNICATION

            // Register Bluetooth headset receiver
            val filter = IntentFilter().apply {
                addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
                addAction(AudioManager.ACTION_HEADSET_PLUG)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.ECLAIR) {
                    addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
                }
            }

            bluetoothReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED -> {
                            val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1)
                            handleScoStateChange(state)
                        }
                        AudioManager.ACTION_HEADSET_PLUG -> {
                            val state = intent.getIntExtra("state", -1)
                            if (state == 0) {
                                // Headset unplugged
                                updateAudioRouting()
                            } else if (state == 1) {
                                // Headset plugged in
                                updateAudioRouting()
                            }
                        }
                        BluetoothAdapter.ACTION_STATE_CHANGED -> {
                            updateAudioRouting()
                        }
                    }
                }
            }

            registerReceiver(bluetoothReceiver, filter)

            // Initialize audio routing
            updateAudioRouting()
        }
    }

    private fun handleScoStateChange(state: Int) {
        when (state) {
            AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
                Log.d(TAG, "Bluetooth SCO connected")
                isBluetoothScoOn = true
                currentAudioRoute = AudioRoute.BLUETOOTH
                updateButtonStates()
            }
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> {
                Log.d(TAG, "Bluetooth SCO disconnected")
                isBluetoothScoOn = false
                // Fallback to speaker or wired headset
                updateAudioRouting()
            }
        }
    }

    private fun updateAudioRouting() {
        audioManager?.let { am ->
            // Priority: Bluetooth > Wired Headset > Preferred (Speaker/Earpiece)

            val hasBluetoothHeadset = isBluetoothAvailable()
            val hasWiredHeadset = isWiredHeadsetConnected()

            when {
                hasBluetoothHeadset -> {
                    // Bluetooth has highest priority
                    if (!isBluetoothScoOn) {
                        am.startBluetoothSco()
                        am.isBluetoothScoOn = true
                    }
                    currentAudioRoute = AudioRoute.BLUETOOTH
                    Log.d(TAG, "Audio routed to Bluetooth")
                }
                hasWiredHeadset -> {
                    // Wired headset second priority
                    if (isBluetoothScoOn) {
                        am.stopBluetoothSco()
                        am.isBluetoothScoOn = false
                    }
                    am.isSpeakerphoneOn = false
                    currentAudioRoute = AudioRoute.WIRED_HEADSET
                    Log.d(TAG, "Audio routed to Wired Headset")
                }
                preferredAudioRoute == AudioRoute.SPEAKER -> {
                    // User prefers speaker
                    if (isBluetoothScoOn) {
                        am.stopBluetoothSco()
                        am.isBluetoothScoOn = false
                    }
                    am.isSpeakerphoneOn = true
                    currentAudioRoute = AudioRoute.SPEAKER
                    Log.d(TAG, "Audio routed to Speaker")
                }
                else -> {
                    // Default to earpiece
                    if (isBluetoothScoOn) {
                        am.stopBluetoothSco()
                        am.isBluetoothScoOn = false
                    }
                    am.isSpeakerphoneOn = false
                    currentAudioRoute = AudioRoute.EARPIECE
                    Log.d(TAG, "Audio routed to Earpiece")
                }
            }

            updateButtonStates()
        }
    }

    private fun isBluetoothAvailable(): Boolean {
        audioManager?.let { am ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                return devices.any {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
                }
            } else {
                // Fallback for older API levels
                @Suppress("DEPRECATION")
                return am.isBluetoothScoAvailableOffCall || am.isBluetoothA2dpOn
            }
        }
        return false
    }

    private fun isWiredHeadsetConnected(): Boolean {
        audioManager?.let { am ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                return devices.any {
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                }
            } else {
                @Suppress("DEPRECATION")
                return am.isWiredHeadsetOn
            }
        }
        return false
    }

    private fun setupLocalMedia() {
        // Create local audio track
        localAudioTrack = LocalAudioTrack.create(this, true, "local_audio")

        // Create camera capturer
        val cameraSource = CameraSource.FRONT_CAMERA
        cameraCapturer = CameraCapturer(this, cameraSource)

        // Create local video track
        localVideoTrack = LocalVideoTrack.create(this, true, cameraCapturer!!, "local_video")
        localVideoTrack?.addSink(localThumbnailView)

        Log.d(TAG, "Local media setup complete")
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

    private fun updateDominantSpeaker(participantIdentity: String?) {
        dominantSpeakerIdentity = participantIdentity

        // Only auto-focus on dominant speaker if user hasn't made a selection
        if (!userHasSelectedParticipant && participantIdentity != null &&
            participantRenderers.containsKey(participantIdentity)) {
            updateFocusedParticipant(participantIdentity, isUserSelection = false)
        }
    }
        remoteParticipantCount++
        participant.setListener(remoteParticipantListener)

        // Create stable renderer for this participant
        val renderer = createParticipantRenderer(participant.identity)
        participantRenderers[participant.identity] = renderer

        Log.d(TAG, "Added remote participant: ${participant.identity}, total: $remoteParticipantCount")

        // Subscribe to existing published video tracks
        participant.remoteVideoTracks.forEach { publication ->
            if (publication.isTrackSubscribed) {
                publication.remoteVideoTrack?.let { track ->
                    addRemoteVideoTrack(participant.identity, track)
                }
            }
        }

        // Update focused participant if this is first remote or no selection yet
        if (focusedParticipantIdentity == null || focusedParticipantIdentity == "local") {
            // Auto-focus on first remote participant
            updateFocusedParticipant(participant.identity, isUserSelection = false)
        }
    }

    private fun removeRemoteParticipant(participant: RemoteParticipant) {
        remoteParticipantCount--

        Log.d(TAG, "Removing participant: ${participant.identity}, remaining: $remoteParticipantCount")

        // Unsubscribe from video tracks
        participant.remoteVideoTracks.forEach { publication ->
            if (publication.isTrackSubscribed) {
                publication.remoteVideoTrack?.let { track ->
                    removeRemoteVideoTrack(participant.identity, track)
                }
            }
        }

        // Remove renderer and clean up views
        participantRenderers.remove(participant.identity)?.let { renderer ->
            runOnUiThread {
                // Remove from primary container if displayed there
                if (renderer.isFocused) {
                    primaryVideoContainer.removeView(renderer.videoView)
                }
                // Remove from thumbnail grid
                thumbnailGridContainer.removeView(renderer.videoView)
            }
        }

        // If this was the focused participant, switch focus
        if (focusedParticipantIdentity == participant.identity) {
            selectNewFocusedParticipant()
        }

        // Update dominant speaker if it was this participant
        if (dominantSpeakerIdentity == participant.identity) {
            dominantSpeakerIdentity = null
        }
    }

    private fun createParticipantRenderer(identity: String): ParticipantRenderer {
        val thumbnailSize = (120 * resources.displayMetrics.density).toInt()
        val thumbnailMargin = (8 * resources.displayMetrics.density).toInt()

        val videoView = VideoView(this).apply {
            layoutParams = LinearLayout.LayoutParams(thumbnailSize, thumbnailSize).apply {
                setMargins(0, 0, 0, thumbnailMargin)
            }
            setBackgroundColor(Color.DKGRAY)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                onThumbnailSelected(identity)
            }

            // 🔥 CRITICAL: Force TextureView rendering to prevent black screens
            setMirror(false)
            setScalingType(com.twilio.video.VideoView.ScalingType.ASPECT_FIT)

            // Force TextureView usage internally (prevents SurfaceView issues)
            try {
                val enableSurfaceViewField = VideoView::class.java.getDeclaredField("enableSurfaceView")
                enableSurfaceViewField.isAccessible = true
                enableSurfaceViewField.setBoolean(this, false) // Force TextureView
                Log.d(TAG, "🎯 Forced TextureView mode for: $identity")
            } catch (e: Exception) {
                Log.w(TAG, "Could not force TextureView mode: ${e.message}")
            }
        }

        Log.d(TAG, "📹 Created TextureView-backed renderer for participant: $identity (hash: ${videoView.hashCode()})")
        return ParticipantRenderer(identity, videoView, null, false)
    }

    private fun onThumbnailSelected(identity: String) {
        Log.d(TAG, "Thumbnail selected: $identity")
        updateFocusedParticipant(identity, isUserSelection = true)
    }

    private fun updateFocusedParticipant(newIdentity: String, isUserSelection: Boolean) {
        if (focusedParticipantIdentity == newIdentity) {
            return // Already focused
        }

        val oldIdentity = focusedParticipantIdentity

        Log.d(TAG, "🔄 Switching focus from $oldIdentity to $newIdentity (userSelection: $isUserSelection)")

        userHasSelectedParticipant = isUserSelection
        focusedParticipantIdentity = newIdentity

        runOnUiThread {
            // Move old focused participant to thumbnail grid
            oldIdentity?.let { oldId ->
                if (oldId == "local") {
                    // Local was focused - remove any duplicate local views from primary
                    primaryVideoContainer.removeAllViews()
                } else {
                    participantRenderers[oldId]?.let { oldRenderer ->
                        val updatedOldRenderer = oldRenderer.copy(isFocused = false)
                        participantRenderers[oldId] = updatedOldRenderer

                        // Critical: Safely move VideoView without recreating
                        if (oldRenderer.videoView.parent == primaryVideoContainer) {
                            primaryVideoContainer.removeView(oldRenderer.videoView)

                            // Restore thumbnail layout params and add to grid
                            val thumbnailSize = (120 * resources.displayMetrics.density).toInt()
                            val thumbnailMargin = (8 * resources.displayMetrics.density).toInt()
                            oldRenderer.videoView.layoutParams = LinearLayout.LayoutParams(thumbnailSize, thumbnailSize).apply {
                                setMargins(0, 0, 0, thumbnailMargin)
                            }
                            thumbnailGridContainer.addView(oldRenderer.videoView)
                            Log.d(TAG, "✓ Moved $oldId from primary to thumbnail")
                        }
                    }
                }
            }

            // Move new focused participant to primary view
            if (newIdentity == "local") {
                // Show local video in primary (rare case)
                primaryVideoContainer.removeAllViews()
                // Critical: NEVER recreate VideoView - create temporary view for local
                val primaryLocalView = VideoView(this@VideoCallActivity).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                }
                localVideoTrack?.addSink(primaryLocalView)
                primaryVideoContainer.addView(primaryLocalView)
                Log.d(TAG, "✓ Focused local video in primary")
            } else {
                participantRenderers[newIdentity]?.let { newRenderer ->
                    val updatedNewRenderer = newRenderer.copy(isFocused = true)
                    participantRenderers[newIdentity] = updatedNewRenderer

                    // Critical: Safely move existing VideoView (NEVER recreate)
                    if (newRenderer.videoView.parent == thumbnailGridContainer) {
                        thumbnailGridContainer.removeView(newRenderer.videoView)
                    }

                    // Ensure primary is clear and add the SAME VideoView
                    primaryVideoContainer.removeAllViews()
                    newRenderer.videoView.layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    primaryVideoContainer.addView(newRenderer.videoView)
                    Log.d(TAG, "✓ Moved $newIdentity from thumbnail to primary (renderer reused)")
        val newFocus = when {
            dominantSpeakerIdentity != null && participantRenderers.containsKey(dominantSpeakerIdentity) -> {
                dominantSpeakerIdentity!!
            }
            participantRenderers.isNotEmpty() -> {
                participantRenderers.keys.first()
            }
            else -> {
                "local"
            }
        }

        updateFocusedParticipant(newFocus, isUserSelection = false)
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
            Log.d(TAG, "🎥 Video track subscribed: ${participant.identity}")
            // Critical: Only add track if participant renderer exists and track not already attached
            participantRenderers[participant.identity]?.let { renderer ->
                if (renderer.videoTrack == null) {
                    addRemoteVideoTrack(participant.identity, track)
                } else {
                    Log.w(TAG, "⚠️ Track already attached to ${participant.identity}, skipping")
                }
            } ?: run {
                Log.w(TAG, "⚠️ No renderer found for ${participant.identity}")
            }
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
        val renderer = participantRenderers[participantIdentity]
        if (renderer == null) {
            Log.w(TAG, "No renderer found for participant: $participantIdentity")
            return
        }

        runOnUiThread {
            // Critical: Check if track already attached to prevent duplicate binding
            if (renderer.videoTrack != null) {
                Log.w(TAG, "Track already attached to participant: $participantIdentity")
                return@runOnUiThread
            }

            // Attach track to the stable video view - ONLY ONCE
            track.addSink(renderer.videoView)
            Log.d(TAG, "✓ Track attached to renderer for: $participantIdentity")

            // Update renderer's track reference
            val updatedRenderer = renderer.copy(videoTrack = track)
            participantRenderers[participantIdentity] = updatedRenderer

            // Ensure view is in the correct container
            if (updatedRenderer.isFocused) {
                // Should be in primary container
                if (renderer.videoView.parent != primaryVideoContainer) {
                    // Critical: Remove from current parent BEFORE adding to new parent
                    (renderer.videoView.parent as? ViewGroup)?.removeView(renderer.videoView)
                    primaryVideoContainer.removeAllViews()
                    renderer.videoView.layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    primaryVideoContainer.addView(renderer.videoView)
                    Log.d(TAG, "✓ Moved focused renderer to primary container: $participantIdentity")
                }
            } else {
                // Should be in thumbnail grid
                if (renderer.videoView.parent != thumbnailGridContainer) {
                    // Critical: Remove from current parent BEFORE adding to new parent
                    (renderer.videoView.parent as? ViewGroup)?.removeView(renderer.videoView)
                    val thumbnailSize = (120 * resources.displayMetrics.density).toInt()
                    val thumbnailMargin = (8 * resources.displayMetrics.density).toInt()
                    renderer.videoView.layoutParams = LinearLayout.LayoutParams(thumbnailSize, thumbnailSize).apply {
                        setMargins(0, 0, 0, thumbnailMargin)
                    }
                    thumbnailGridContainer.addView(renderer.videoView)
                    Log.d(TAG, "✓ Moved renderer to thumbnail grid: $participantIdentity")
                }
            }

            Log.d(TAG, "✓ Added video track to participant: $participantIdentity (focused: ${updatedRenderer.isFocused})")
        }
    }

    private fun removeRemoteVideoTrack(participantIdentity: String, track: RemoteVideoTrack) {
        val renderer = participantRenderers[participantIdentity]
        if (renderer == null) {
            Log.w(TAG, "No renderer found for participant: $participantIdentity")
            return
        }

        runOnUiThread {
            // Remove track from video view
            track.removeSink(renderer.videoView)

            // Clear track reference
            val updatedRenderer = renderer.copy(videoTrack = null)
            participantRenderers[participantIdentity] = updatedRenderer

            Log.d(TAG, "✓ Removed video track from participant: $participantIdentity")
        }
    }

    private fun checkAutoClose() {
        if (remoteParticipantCount == 0 && callState == CallState.CONNECTED) {
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
            // Mute button - highlighted when MUTED
            muteButton.isEnabled = isConnected
            muteButton.isSelected = isAudioMuted

            // Video button - highlighted when DISABLED (showing icon state)
            videoButton.isEnabled = isConnected
            videoButton.isSelected = !isVideoEnabled

            // Flip button - enabled only when connected and video is on
            flipButton.isEnabled = isConnected && isVideoEnabled
            flipButton.isSelected = false

            // Speaker button - show current audio route state
            // Highlight if using speaker (not Bluetooth or headset)
            speakerButton.isEnabled = isConnected &&
                currentAudioRoute != AudioRoute.BLUETOOTH &&
                currentAudioRoute != AudioRoute.WIRED_HEADSET
            speakerButton.isSelected = currentAudioRoute == AudioRoute.SPEAKER

            // Hangup button - enabled during joining and connected
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

        Log.d(TAG, "Disconnecting from room")
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

        if (isAudioMuted == muted) {
            return // Already in desired state
        }

        isAudioMuted = muted
        localAudioTrack?.enable(!muted)
        updateButtonStates()
        Log.d(TAG, "Audio muted: $muted")
    }

    fun enableVideo(enabled: Boolean) {
        if (callState != CallState.CONNECTED) {
            Log.w(TAG, "Cannot toggle video, not connected. State: $callState")
            return
        }

        if (isVideoEnabled == enabled) {
            return // Already in desired state
        }

        isVideoEnabled = enabled
        localVideoTrack?.enable(enabled)
        updateButtonStates()
        Log.d(TAG, "Video enabled: $enabled")
    }

    fun flipCamera() {
        if (callState != CallState.CONNECTED || !isVideoEnabled) {
            Log.w(TAG, "Cannot flip camera. State: $callState, VideoEnabled: $isVideoEnabled")
            return
        }

        cameraCapturer?.switchCamera()
        Log.d(TAG, "Camera flipped")
    }

    fun setSpeaker(enabled: Boolean) {
        if (callState != CallState.CONNECTED) {
            Log.w(TAG, "Cannot toggle speaker, not connected. State: $callState")
            return
        }

        // Speaker toggle only works if not using Bluetooth or wired headset
        if (currentAudioRoute == AudioRoute.BLUETOOTH ||
            currentAudioRoute == AudioRoute.WIRED_HEADSET) {
            Log.w(TAG, "Cannot toggle speaker while using ${currentAudioRoute}")
            return
        }

        preferredAudioRoute = if (enabled) AudioRoute.SPEAKER else AudioRoute.EARPIECE
        updateAudioRouting()
        Log.d(TAG, "Speaker enabled: $enabled")
    }

    private fun toggleAudioMute() {
        muteAudio(!isAudioMuted)
    }

    private fun toggleVideo() {
        enableVideo(!isVideoEnabled)
    }

    private fun toggleSpeaker() {
        setSpeaker(currentAudioRoute != AudioRoute.SPEAKER)
    }

    private fun cleanup() {
        Log.d(TAG, "Cleaning up resources")

        // Cancel any pending dominant speaker updates
        dominantSpeakerDebounceRunnable?.let { mainHandler.removeCallbacks(it) }
        dominantSpeakerDebounceRunnable = null

        // Clean up local media
        localVideoTrack?.let {
            it.removeSink(localThumbnailView)
            it.release()
        }
        localVideoTrack = null

        localAudioTrack?.release()
        localAudioTrack = null

        cameraCapturer?.stopCapture()
        cameraCapturer = null

        // Clean up all participant renderers
        runOnUiThread {
            participantRenderers.values.forEach { renderer ->
                renderer.videoTrack?.removeSink(renderer.videoView)
                primaryVideoContainer.removeView(renderer.videoView)
                thumbnailGridContainer.removeView(renderer.videoView)
            }
        }
        participantRenderers.clear()

        // Reset state
        dominantSpeakerIdentity = null
        focusedParticipantIdentity = null
        userHasSelectedParticipant = false

        // Clean up audio
        audioManager?.let { am ->
            if (isBluetoothScoOn) {
                am.stopBluetoothSco()
                am.isBluetoothScoOn = false
                isBluetoothScoOn = false
            }
            am.mode = AudioManager.MODE_NORMAL
        }

        // Unregister Bluetooth receiver
        bluetoothReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering Bluetooth receiver: ${e.message}")
            }
        }
        bluetoothReceiver = null

        room = null
        localParticipant = null
    }

    override fun onDestroy() {
        Log.d(TAG, "Activity destroyed")
        cleanup()
        instance = null

        // Reset state
        transitionToState(CallState.DISCONNECTED)

        super.onDestroy()
    }
}
