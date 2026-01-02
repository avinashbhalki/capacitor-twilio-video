package com.avinashbhalki.capacitor.twilio.video

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
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
    private var isAudioMuted = false
    private var isVideoEnabled = true
    private var isSpeakerEnabled = true
    private var accessToken: String? = null
    private var roomName: String? = null
    private var remoteParticipantCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        // Create full-screen layout
        createFullScreenLayout()

        accessToken = intent.getStringExtra("token")
        roomName = intent.getStringExtra("roomName")

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        setupLocalMedia()
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
            setBackgroundColor(android.graphics.Color.GRAY)
        }
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

            TwilioVideoPlugin.getInstance()?.notifyRoomConnected(room.name)

            // Handle existing participants
            room.remoteParticipants.forEach { participant ->
                addRemoteParticipant(participant)
            }
        }

        override fun onReconnecting(room: Room, twilioException: TwilioException) {
            Log.d(TAG, "Reconnecting to room: ${room.name}")
        }

        override fun onReconnected(room: Room) {
            Log.d(TAG, "Reconnected to room: ${room.name}")
        }

        override fun onConnectFailure(room: Room, twilioException: TwilioException) {
            Log.e(TAG, "Connect failure: ${twilioException.message}")
            TwilioVideoPlugin.getInstance()?.notifyRoomError(
                twilioException.code.toString(),
                twilioException.message ?: "Connection failed",
                true
            )
            finish()
        }

        override fun onDisconnected(room: Room, twilioException: TwilioException?) {
            Log.d(TAG, "Disconnected from room: ${room.name}")
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
            TwilioVideoPlugin.getInstance()?.notifyDominantSpeakerChanged(remoteParticipant?.identity)
        }
    }

    private fun addRemoteParticipant(participant: RemoteParticipant) {
        remoteParticipantCount++
        participant.setListener(remoteParticipantListener)

        participant.remoteVideoTracks.forEach { publication ->
            if (publication.isTrackSubscribed) {
                publication.remoteVideoTrack?.let { addRemoteVideoTrack(it) }
            }
        }
    }

    private fun removeRemoteParticipant(participant: RemoteParticipant) {
        remoteParticipantCount--
        participant.remoteVideoTracks.forEach { publication ->
            if (publication.isTrackSubscribed) {
                publication.remoteVideoTrack?.let { removeRemoteVideoTrack(it) }
            }
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
            addRemoteVideoTrack(track)
        }

        override fun onVideoTrackUnsubscribed(
            participant: RemoteParticipant,
            publication: RemoteVideoTrackPublication,
            track: RemoteVideoTrack
        ) {
            Log.d(TAG, "Video track unsubscribed: ${participant.identity}")
            removeRemoteVideoTrack(track)
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

    private fun addRemoteVideoTrack(track: RemoteVideoTrack) {
        runOnUiThread {
            primaryVideoView.removeAllViews()
            track.addSink(primaryVideoView)
        }
    }

    private fun removeRemoteVideoTrack(track: RemoteVideoTrack) {
        runOnUiThread {
            track.removeSink(primaryVideoView)
        }
    }

    private fun checkAutoClose() {
        if (remoteParticipantCount == 0) {
            Log.d(TAG, "All remote participants left, auto-closing")
            TwilioVideoPlugin.getInstance()?.notifyRoomAutoClosed("last-participant-left")
            disconnect()
        }
    }

    fun disconnect() {
        room?.disconnect()
        cleanup()
        runOnUiThread {
            finish()
        }
    }

    fun muteAudio(muted: Boolean) {
        isAudioMuted = muted
        localAudioTrack?.enable(!muted)
    }

    fun enableVideo(enabled: Boolean) {
        isVideoEnabled = enabled
        localVideoTrack?.enable(enabled)
    }

    fun flipCamera() {
        cameraCapturer?.switchCamera()
    }

    fun setSpeaker(enabled: Boolean) {
        isSpeakerEnabled = enabled
        audioManager?.let {
            it.isSpeakerphoneOn = enabled
        }
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
        localVideoTrack?.let {
            it.removeSink(thumbnailVideoView)
            it.release()
        }
        localVideoTrack = null

        localAudioTrack?.release()
        localAudioTrack = null

        cameraCapturer?.stopCapture()
        cameraCapturer = null

        room = null
        localParticipant = null
    }

    override fun onDestroy() {
        cleanup()
        instance = null
        super.onDestroy()
    }
}
