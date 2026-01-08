import UIKit
import TwilioVideo
import AVFoundation

class VideoCallViewController: UIViewController {

    // MARK: - Call State Machine
    enum CallState {
        case idle            // No active call
        case joining         // joinRoom invoked, not yet connected
        case connected       // Room connected
        case disconnecting   // leaveRoom or auto-close in progress
        case disconnected    // Call fully ended
    }

    // MARK: - Audio Routing State
    enum AudioRoute {
        case bluetooth
        case wiredHeadset
        case speaker
        case earpiece
    }

    // MARK: - Participant Renderer
    struct ParticipantRenderer {
        let identity: String
        let videoView: VideoView
        var videoTrack: RemoteVideoTrack?
        var isFocused: Bool
    }

    // MARK: - Properties
    var accessToken: String?
    var roomName: String?

    private var room: Room?
    private var localParticipant: LocalParticipant?
    private var localVideoTrack: LocalVideoTrack?
    private var localAudioTrack: LocalAudioTrack?
    private var camera: CameraSource?
    private var remoteParticipantCount = 0

    // Call state
    private var callState: CallState = .idle

    // UI Elements
    private var primaryVideoContainer: UIView!
    private var thumbnailGridContainer: UIStackView!
    private var localThumbnailView: VideoView!
    private var controlsContainer: UIView!
    private var muteButton: UIButton!
    private var videoButton: UIButton!
    private var flipButton: UIButton!
    private var speakerButton: UIButton!
    private var hangupButton: UIButton!

    // State
    private var isAudioMuted = false
    private var isVideoEnabled = true
    private var currentAudioRoute: AudioRoute = .speaker
    private var preferredAudioRoute: AudioRoute = .speaker

    // Participant Rendering Manager
    private var participantRenderers: [String: ParticipantRenderer] = [:]
    private var focusedParticipantIdentity: String? // User-selected or dominant speaker
    private var dominantSpeakerIdentity: String?
    private var userHasSelectedParticipant = false // User selection overrides dominant speaker
    private var dominantSpeakerDebounceTimer: Timer?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        setupFullScreenUI()
        setupAudioSession()
        setupLocalMedia()

        // Transition to joining state
        transitionToState(.joining)
        connectToRoom()
    }

    // MARK: - UI Setup
    private func setupFullScreenUI() {
        view.backgroundColor = .black

        // Primary video container (remote participant - full screen)
        primaryVideoContainer = UIView(frame: view.bounds)
        primaryVideoContainer.backgroundColor = .black
        primaryVideoContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(primaryVideoContainer)

        // Thumbnail grid container (top-right, overlays primary video)
        thumbnailGridContainer = UIStackView()
        thumbnailGridContainer.axis = .vertical
        thumbnailGridContainer.distribution = .equalSpacing
        thumbnailGridContainer.alignment = .fill
        thumbnailGridContainer.spacing = 8
        thumbnailGridContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumbnailGridContainer)

        NSLayoutConstraint.activate([
            thumbnailGridContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            thumbnailGridContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            thumbnailGridContainer.widthAnchor.constraint(equalToConstant: 120)
        ])

        // Local video thumbnail (always at top of grid)
        localThumbnailView = VideoView(frame: .zero)
        localThumbnailView.contentMode = .scaleAspectFill
        localThumbnailView.backgroundColor = .darkGray
        localThumbnailView.layer.cornerRadius = 8
        localThumbnailView.clipsToBounds = true
        localThumbnailView.translatesAutoresizingMaskIntoConstraints = false

        // Make clickable to select local video as focused
        let localTapGesture = UITapGestureRecognizer(target: self, action: #selector(localThumbnailTapped))
        localThumbnailView.addGestureRecognizer(localTapGesture)
        localThumbnailView.isUserInteractionEnabled = true

        thumbnailGridContainer.addArrangedSubview(localThumbnailView)

        NSLayoutConstraint.activate([
            localThumbnailView.heightAnchor.constraint(equalToConstant: 120)
        ])

        // Controls container at bottom
        controlsContainer = UIView()
        controlsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsContainer)

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controlsContainer.heightAnchor.constraint(equalToConstant: 80)
        ])

        // Add blur effect for modern appearance
        let blurEffect = UIBlurEffect(style: .dark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.insertSubview(blurView, at: 0)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor)
        ])

        setupControls()
    }

    @objc private func localThumbnailTapped() {
        onThumbnailSelected("local")
    }

    private func setupControls() {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: controlsContainer.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: controlsContainer.trailingAnchor, constant: -16)
        ])

        muteButton = createControlButton(title: "Mute")
        muteButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        muteButton.setImage(UIImage(systemName: "mic.slash.fill"), for: .selected)
        muteButton.addTarget(self, action: #selector(toggleAudioMute), for: .touchUpInside)

        videoButton = createControlButton(title: "Video")
        videoButton.setImage(UIImage(systemName: "video.fill"), for: .normal)
        videoButton.setImage(UIImage(systemName: "video.slash.fill"), for: .selected)
        videoButton.addTarget(self, action: #selector(toggleVideo), for: .touchUpInside)

        flipButton = createControlButton(title: "Flip Camera")
        flipButton.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)

        speakerButton = createControlButton(title: "Speaker/Bluetooth")
        speakerButton.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        speakerButton.setImage(UIImage(systemName: "bluetooth"), for: .selected)
        speakerButton.addTarget(self, action: #selector(toggleSpeaker), for: .touchUpInside)

        hangupButton = createControlButton(title: "End Call")
        hangupButton.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        hangupButton.backgroundColor = .systemRed
        // Override the configuration update handler for hangup button to keep it red
        hangupButton.configurationUpdateHandler = { btn in
            if !btn.isEnabled {
                btn.backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
                btn.tintColor = .white
                btn.alpha = 0.5
            } else {
                btn.backgroundColor = .systemRed
                btn.tintColor = .white
                btn.alpha = 1.0
            }
        }
        hangupButton.addTarget(self, action: #selector(disconnect), for: .touchUpInside)

        stackView.addArrangedSubview(muteButton)
        stackView.addArrangedSubview(videoButton)
        stackView.addArrangedSubview(flipButton)
        stackView.addArrangedSubview(speakerButton)
        stackView.addArrangedSubview(hangupButton)
    }

    private func createControlButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("", for: .normal) // Clear title, use icons only
        button.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        button.layer.cornerRadius = 24
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.accessibilityLabel = title

        // Set up stateful colors - use configurationUpdateHandler for proper state handling
        button.backgroundColor = .systemGray
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.lightGray, for: .disabled)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Add configuration update handler for better visual feedback
        button.configurationUpdateHandler = { btn in
            if !btn.isEnabled {
                btn.backgroundColor = UIColor.systemGray.withAlphaComponent(0.3)
                btn.tintColor = .lightGray
                btn.alpha = 0.5
            } else if btn.isSelected {
                btn.backgroundColor = .systemGreen
                btn.tintColor = .white
                btn.alpha = 1.0
            } else {
                btn.backgroundColor = .systemGray
                btn.tintColor = .white
                btn.alpha = 1.0
            }
        }

        return button
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Configure for video chat with Bluetooth support
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)

            // Default to speaker
            try audioSession.overrideOutputAudioPort(.speaker)
            currentAudioRoute = .speaker
            preferredAudioRoute = .speaker

            // Observe audio route changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: audioSession
            )

            print("Audio session configured successfully")
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .newDeviceAvailable:
            // New device connected (e.g., Bluetooth headset)
            updateAudioRouting()
        case .oldDeviceUnavailable:
            // Device disconnected (e.g., Bluetooth headset unplugged)
            updateAudioRouting()
        default:
            break
        }
    }

    private func updateAudioRouting() {
        let audioSession = AVAudioSession.sharedInstance()

        // Detect available routes
        let currentRoute = audioSession.currentRoute
        let hasBluetoothRoute = currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP || output.portType == .bluetoothLE
        }
        let hasWiredHeadset = currentRoute.outputs.contains { output in
            output.portType == .headphones || output.portType == .headsetMic
        }

        do {
            // Priority: Bluetooth > Wired Headset > Preferred (Speaker/Earpiece)
            if hasBluetoothRoute {
                // Bluetooth has highest priority - don't override
                currentAudioRoute = .bluetooth
                print("Audio routed to Bluetooth")
            } else if hasWiredHeadset {
                // Wired headset second priority
                try audioSession.overrideOutputAudioPort(.none)
                currentAudioRoute = .wiredHeadset
                print("Audio routed to Wired Headset")
            } else if preferredAudioRoute == .speaker {
                // User prefers speaker
                try audioSession.overrideOutputAudioPort(.speaker)
                currentAudioRoute = .speaker
                print("Audio routed to Speaker")
            } else {
                // Default to earpiece
                try audioSession.overrideOutputAudioPort(.none)
                currentAudioRoute = .earpiece
                print("Audio routed to Earpiece")
            }

            updateButtonStates()
        } catch {
            print("Failed to update audio routing: \(error.localizedDescription)")
        }
    }

    // MARK: - Local Media Setup
    private func setupLocalMedia() {
        // Create local audio track
        localAudioTrack = LocalAudioTrack(options: nil, enabled: true, name: "local_audio")

        // Request camera access and create video track
        if let camera = CameraSource(delegate: self) {
            self.camera = camera
            localVideoTrack = LocalVideoTrack(source: camera, enabled: true, name: "local_video")

            // Render local video in thumbnail
            if let renderer = localThumbnailView {
                localVideoTrack?.addRenderer(renderer)
            }

            // Start camera
            if let device = frontCamera() {
                camera.startCapture(device: device) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        print("Camera start capture failed: \(error.localizedDescription)")
                    } else {
                        print("Local camera started successfully")
                    }
                }
            } else {
                print("Failed to get front camera device")
            }
        }
    }

    private func frontCamera() -> AVCaptureDevice? {
        return CameraSource.captureDevice(position: .front)
    }

    private func backCamera() -> AVCaptureDevice? {
        return CameraSource.captureDevice(position: .back)
    }

    // MARK: - Room Connection
    private func connectToRoom() {
        guard let token = accessToken, let name = roomName else {
            print("Missing access token or room name")
            return
        }

        let connectOptions = ConnectOptions(token: token) { builder in
            builder.roomName = name

            if let audioTrack = self.localAudioTrack {
                builder.audioTracks = [audioTrack]
            }

            if let videoTrack = self.localVideoTrack {
                builder.videoTracks = [videoTrack]
            }

            builder.isDominantSpeakerEnabled = true
            builder.isNetworkQualityEnabled = true
            builder.networkQualityConfiguration = NetworkQualityConfiguration(
                localVerbosity: .minimal,
                remoteVerbosity: .minimal
            )
        }

        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)
    }

    // MARK: - Control Actions
    @objc func toggleAudioMute() {
        muteAudio(muted: !isAudioMuted)
    }

    @objc func toggleVideo() {
        enableVideo(enabled: !isVideoEnabled)
    }

    @objc func toggleSpeaker() {
        setSpeaker(enabled: !isSpeakerEnabled)
    }

    func muteAudio(muted: Bool) {
        guard callState == .connected else {
            print("Cannot mute audio, not connected. State: \(callState)")
            return
        }

        guard isAudioMuted != muted else {
            return // Already in desired state
        }

        isAudioMuted = muted
        localAudioTrack?.isEnabled = !muted
        updateButtonStates()
        print("Audio muted: \(muted)")
    }

    func enableVideo(enabled: Bool) {
        guard callState == .connected else {
            print("Cannot toggle video, not connected. State: \(callState)")
            return
        }

        guard isVideoEnabled != enabled else {
            return // Already in desired state
        }

        isVideoEnabled = enabled
        localVideoTrack?.isEnabled = enabled
        updateButtonStates()
        print("Video enabled: \(enabled)")
    }

    @objc func flipCamera() {
        guard callState == .connected, isVideoEnabled, let camera = camera else {
            print("Cannot flip camera. State: \(callState), VideoEnabled: \(isVideoEnabled)")
            return
        }

        let newDevice: AVCaptureDevice?
        if camera.device?.position == .front {
            newDevice = backCamera()
        } else {
            newDevice = frontCamera()
        }

        if let device = newDevice {
            camera.selectCaptureDevice(device) { (captureDevice, videoFormat, error) in
                if let error = error {
                    print("Camera flip failed: \(error.localizedDescription)")
                } else {
                    print("Camera flipped successfully")
                }
            }
        }
    }

    func setSpeaker(enabled: Bool) {
        guard callState == .connected else {
            print("Cannot toggle speaker, not connected. State: \(callState)")
            return
        }

        // Speaker toggle only works if not using Bluetooth or wired headset
        if currentAudioRoute == .bluetooth || currentAudioRoute == .wiredHeadset {
            print("Cannot toggle speaker while using \(currentAudioRoute)")
            return
        }

        preferredAudioRoute = enabled ? .speaker : .earpiece
        updateAudioRouting()
        print("Speaker enabled: \(enabled)")
    }

    @objc func disconnect() {
        guard callState != .disconnecting && callState != .disconnected else {
            print("Already disconnecting or disconnected, ignoring")
            return
        }

        print("Disconnecting from room")
        transitionToState(.disconnecting)
        room?.disconnect()
        cleanup()
        dismiss(animated: true, completion: nil)
    }

    @objc private func toggleSpeaker() {
        setSpeaker(currentAudioRoute != .speaker)
    }

    // MARK: - Cleanup
    private func cleanup() {
        print("Cleaning up resources")

        // Cancel any pending dominant speaker updates
        dominantSpeakerDebounceTimer?.invalidate()
        dominantSpeakerDebounceTimer = nil

        // Remove audio route observer
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        // Clean up local media
        localVideoTrack?.removeRenderer(localThumbnailView)
        localVideoTrack = nil
        localAudioTrack = nil
        camera?.stopCapture()
        camera = nil
        room = nil
        localParticipant = nil

        // Clean up all participant renderers
        for (_, renderer) in participantRenderers {
            renderer.videoTrack?.removeRenderer(renderer.videoView)
            renderer.videoView.removeFromSuperview()
        }
        participantRenderers.removeAll()

        // Reset state
        dominantSpeakerIdentity = nil
        focusedParticipantIdentity = nil
        userHasSelectedParticipant = false

        // Reset audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    deinit {
        cleanup()
        print("VideoCallViewController deallocated")
    }

    // MARK: - Auto-Close Logic
    private func checkAutoClose() {
        if remoteParticipantCount == 0 && callState == .connected {
            print("All remote participants left, auto-closing")
            TwilioVideoPlugin.getInstance()?.notifyRoomAutoClosed(reason: "last-participant-left")
            disconnect()
        }
    }

    // MARK: - Call State Machine

    private func transitionToState(_ newState: CallState) {
        let oldState = callState

        // Validate state transition
        let isValidTransition: Bool
        switch (oldState, newState) {
        case (.idle, .joining),
             (.joining, .connected),
             (.joining, .disconnected),      // Failed to connect
             (.connected, .disconnecting),
             (.disconnecting, .disconnected),
             (.connected, .disconnected):    // Abnormal disconnect
            isValidTransition = true
        default:
            isValidTransition = (oldState == newState)  // Allow same state
        }

        guard isValidTransition else {
            print("Invalid state transition: \(oldState) -> \(newState)")
            return
        }

        print("Call state transition: \(oldState) -> \(newState)")
        callState = newState

        // Update UI based on new state
        DispatchQueue.main.async {
            self.updateButtonStates()
        }
    }

    private func updateButtonStates() {
        let isConnected = (callState == .connected)

        DispatchQueue.main.async {
            // Mute button - highlighted when MUTED
            self.muteButton.isEnabled = isConnected
            self.muteButton.isSelected = self.isAudioMuted

            // Video button - highlighted when DISABLED (showing off state)
            self.videoButton.isEnabled = isConnected
            self.videoButton.isSelected = !self.isVideoEnabled

            // Flip button - enabled only when connected and video is on
            self.flipButton.isEnabled = isConnected && self.isVideoEnabled
            self.flipButton.isSelected = false

            // Speaker button - show current audio route state
            // Selected when using Bluetooth, enabled when using speaker/earpiece
            self.speakerButton.isEnabled = isConnected
            self.speakerButton.isSelected = self.currentAudioRoute == .bluetooth

            // Hangup button - enabled during joining and connected
            self.hangupButton.isEnabled = (self.callState == .joining ||
                                          self.callState == .connected)
        }
    }
}

// MARK: - Room Delegate
extension VideoCallViewController: RoomDelegate {
    func roomDidConnect(room: Room) {
        print("Connected to room: \(room.name)")
        localParticipant = room.localParticipant

        // Transition to CONNECTED state
        transitionToState(.connected)

        TwilioVideoPlugin.getInstance()?.notifyRoomConnected(roomName: room.name)

        // Handle existing participants
        for participant in room.remoteParticipants {
            addRemoteParticipant(participant)
        }

        // Update UI to reflect connected state
        updateButtonStates()
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        print("Failed to connect to room: \(error.localizedDescription)")

        // Transition to DISCONNECTED on failure
        transitionToState(.disconnected)

        TwilioVideoPlugin.getInstance()?.notifyRoomError(
            code: "CONNECT_FAILED",
            message: error.localizedDescription,
            isFatal: true
        )
        dismiss(animated: true, completion: nil)
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        print("Disconnected from room: \(room.name)")

        // Transition to DISCONNECTED
        transitionToState(.disconnected)

        TwilioVideoPlugin.getInstance()?.notifyRoomDisconnected(
            roomName: room.name,
            reason: error?.localizedDescription
        )
        cleanup()
    }

    func roomIsReconnecting(room: Room, error: Error) {
        print("Reconnecting to room: \(room.name)")
    }

    func roomDidReconnect(room: Room) {
        print("Reconnected to room: \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        print("Participant connected: \(participant.identity)")
        addRemoteParticipant(participant)
        TwilioVideoPlugin.getInstance()?.notifyParticipantJoined(identity: participant.identity)
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        print("Participant disconnected: \(participant.identity)")
        removeRemoteParticipant(participant)
        TwilioVideoPlugin.getInstance()?.notifyParticipantLeft(identity: participant.identity)

        // Check for auto-close
        checkAutoClose()
    }

    func dominantSpeakerDidChange(room: Room, participant: RemoteParticipant?) {
        print("Dominant speaker: \(participant?.identity ?? "nil")")

        // Debounce dominant speaker changes to avoid flicker
        dominantSpeakerDebounceTimer?.invalidate()

        dominantSpeakerDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.updateDominantSpeaker(participant?.identity)
        }

        TwilioVideoPlugin.getInstance()?.notifyDominantSpeakerChanged(identity: participant?.identity)
    }
}

// MARK: - Remote Participant Management
extension VideoCallViewController {
    private func addRemoteParticipant(_ participant: RemoteParticipant) {
        remoteParticipantCount += 1
        participant.delegate = self

        // Create stable renderer for this participant
        let renderer = createParticipantRenderer(identity: participant.identity)
        participantRenderers[participant.identity] = renderer

        print("Added remote participant: \(participant.identity), total: \(remoteParticipantCount)")

        // Subscribe to existing published video tracks
        for publication in participant.remoteVideoTracks {
            if let track = publication.remoteTrack, publication.isTrackSubscribed {
                addRemoteVideoTrack(participant.identity, track: track)
            }
        }

        // Update focused participant if this is first remote or no selection yet
        if focusedParticipantIdentity == nil || focusedParticipantIdentity == "local" {
            // Auto-focus on first remote participant
            updateFocusedParticipant(participant.identity, isUserSelection: false)
        }
    }

    private func removeRemoteParticipant(_ participant: RemoteParticipant) {
        remoteParticipantCount -= 1

        print("Removing participant: \(participant.identity), remaining: \(remoteParticipantCount)")

        // Unsubscribe from video tracks
        for publication in participant.remoteVideoTracks {
            if let track = publication.remoteTrack, publication.isTrackSubscribed {
                removeRemoteVideoTrack(participant.identity, track: track)
            }
        }

        // Remove renderer and clean up views
        if let renderer = participantRenderers.removeValue(forKey: participant.identity) {
            DispatchQueue.main.async {
                // Remove from primary container if displayed there
                if renderer.isFocused {
                    renderer.videoView.removeFromSuperview()
                }
                // Remove from thumbnail grid
                renderer.videoView.removeFromSuperview()
            }
        }

        // If this was the focused participant, switch focus
        if focusedParticipantIdentity == participant.identity {
            selectNewFocusedParticipant()
        }

        // Update dominant speaker if it was this participant
        if dominantSpeakerIdentity == participant.identity {
            dominantSpeakerIdentity = nil
        }
    }

    private func createParticipantRenderer(identity: String) -> ParticipantRenderer {
        let videoView = VideoView(frame: .zero)
        videoView.contentMode = .scaleAspectFill
        videoView.backgroundColor = .darkGray
        videoView.layer.cornerRadius = 8
        videoView.clipsToBounds = true
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped(_:)))
        videoView.addGestureRecognizer(tapGesture)

        print("Created VideoView for participant: \(identity)")
        return ParticipantRenderer(identity: identity, videoView: videoView, videoTrack: nil, isFocused: false)
    }

    @objc private func thumbnailTapped(_ gesture: UITapGestureRecognizer) {
        guard let videoView = gesture.view else { return }

        // Find the participant identity for this video view
        for (identity, renderer) in participantRenderers {
            if renderer.videoView == videoView {
                onThumbnailSelected(identity)
                break
            }
        }
    }

    private func onThumbnailSelected(_ identity: String) {
        print("Thumbnail selected: \(identity)")
        updateFocusedParticipant(identity, isUserSelection: true)
    }

    private func updateFocusedParticipant(_ newIdentity: String, isUserSelection: Bool) {
        guard focusedParticipantIdentity != newIdentity else {
            return // Already focused
        }

        let oldIdentity = focusedParticipantIdentity

        print("🔄 Switching focus from \(oldIdentity ?? "nil") to \(newIdentity) (userSelection: \(isUserSelection))")

        userHasSelectedParticipant = isUserSelection
        focusedParticipantIdentity = newIdentity

        DispatchQueue.main.async {
            // Move old focused participant to thumbnail grid
            if let oldId = oldIdentity {
                if oldId == "local" {
                    // Local was focused - remove any duplicate local views from primary
                    self.primaryVideoContainer.subviews.forEach { $0.removeFromSuperview() }
                } else if var oldRenderer = self.participantRenderers[oldId] {
                    oldRenderer.isFocused = false
                    self.participantRenderers[oldId] = oldRenderer

                    // Critical: Safely move TVIVideoView without recreating
                    if oldRenderer.videoView.superview == self.primaryVideoContainer {
                        oldRenderer.videoView.removeFromSuperview()

                        // Add back to thumbnail grid with proper constraints
                        self.thumbnailGridContainer.addArrangedSubview(oldRenderer.videoView)
                        NSLayoutConstraint.activate([
                            oldRenderer.videoView.heightAnchor.constraint(equalToConstant: 120)
                        ])
                        print("✅ Moved \(oldId) from primary to thumbnail")
                    }
                }
            }

            // Move new focused participant to primary view
            if newIdentity == "local" {
                // Show local video in primary (rare case)
                self.primaryVideoContainer.subviews.forEach { $0.removeFromSuperview() }

                // Critical: NEVER recreate VideoView - create temporary view for local
                let primaryLocalView = VideoView(frame: .zero)
                primaryLocalView.contentMode = .scaleAspectFill
                primaryLocalView.translatesAutoresizingMaskIntoConstraints = false
                self.primaryVideoContainer.addSubview(primaryLocalView)

                // Apply FULL AutoLayout constraints
                NSLayoutConstraint.activate([
                    primaryLocalView.leadingAnchor.constraint(equalTo: self.primaryVideoContainer.leadingAnchor),
                    primaryLocalView.trailingAnchor.constraint(equalTo: self.primaryVideoContainer.trailingAnchor),
                    primaryLocalView.topAnchor.constraint(equalTo: self.primaryVideoContainer.topAnchor),
                    primaryLocalView.bottomAnchor.constraint(equalTo: self.primaryVideoContainer.bottomAnchor)
                ])

                // Force layout pass IMMEDIATELY
                self.primaryVideoContainer.layoutIfNeeded()
                primaryLocalView.layoutIfNeeded()

                self.localVideoTrack?.addRenderer(primaryLocalView)
                print("✅ Focused local video in primary (frame: \(primaryLocalView.frame))")
            } else if var newRenderer = self.participantRenderers[newIdentity] {
                newRenderer.isFocused = true
                self.participantRenderers[newIdentity] = newRenderer

                // Critical: Safely move existing TVIVideoView (NEVER recreate)
                if newRenderer.videoView.superview == self.thumbnailGridContainer {
                    newRenderer.videoView.removeFromSuperview()
                }

                // Ensure primary is clear and add the SAME VideoView
                self.primaryVideoContainer.subviews.forEach { $0.removeFromSuperview() }

                // Apply proper AutoLayout constraints (MANDATORY for TVIVideoView)
                newRenderer.videoView.translatesAutoresizingMaskIntoConstraints = false
                self.primaryVideoContainer.addSubview(newRenderer.videoView)

                NSLayoutConstraint.activate([
                    newRenderer.videoView.leadingAnchor.constraint(equalTo: self.primaryVideoContainer.leadingAnchor),
                    newRenderer.videoView.trailingAnchor.constraint(equalTo: self.primaryVideoContainer.trailingAnchor),
                    newRenderer.videoView.topAnchor.constraint(equalTo: self.primaryVideoContainer.topAnchor),
                    newRenderer.videoView.bottomAnchor.constraint(equalTo: self.primaryVideoContainer.bottomAnchor)
                ])

                // Force layout pass IMMEDIATELY (critical for TVIVideoView rendering)
                self.primaryVideoContainer.layoutIfNeeded()
                newRenderer.videoView.layoutIfNeeded()

                print("✅ Moved \(newIdentity) from thumbnail to primary (renderer reused, frame: \(newRenderer.videoView.frame))")
            }
        }
    }

    private func selectNewFocusedParticipant() {
        // Priority: Dominant speaker > First available participant > Local
        let newFocus: String
        if let dominantId = dominantSpeakerIdentity, participantRenderers.keys.contains(dominantId) {
            newFocus = dominantId
        } else if let firstId = participantRenderers.keys.first {
            newFocus = firstId
        } else {
            newFocus = "local"
        }

        updateFocusedParticipant(newFocus, isUserSelection: false)
    }

    private func addRemoteVideoTrack(_ participantIdentity: String, track: RemoteVideoTrack) {
        guard var renderer = participantRenderers[participantIdentity] else {
            print("❌ No renderer found for participant: \(participantIdentity)")
            return
        }

        DispatchQueue.main.async {
            // Critical: Check if track already attached to prevent duplicate binding
            if renderer.videoTrack != nil {
                print("⚠️ Track already attached to participant: \(participantIdentity)")
                return
            }

            // Attach track to the stable video view - ONLY ONCE
            track.addRenderer(renderer.videoView)
            print("✅ Track attached to renderer for: \(participantIdentity)")

            // Update renderer's track reference
            renderer.videoTrack = track
            self.participantRenderers[participantIdentity] = renderer

            // Ensure view is in the correct container
            if renderer.isFocused {
                // Should be in primary container
                if renderer.videoView.superview != self.primaryVideoContainer {
                    // Critical: Remove from current superview BEFORE adding to new parent
                    renderer.videoView.removeFromSuperview()
                    self.primaryVideoContainer.subviews.forEach { $0.removeFromSuperview() }

                    // Apply proper AutoLayout constraints (MANDATORY for TVIVideoView)
                    renderer.videoView.translatesAutoresizingMaskIntoConstraints = false
                    self.primaryVideoContainer.addSubview(renderer.videoView)

                    NSLayoutConstraint.activate([
                        renderer.videoView.leadingAnchor.constraint(equalTo: self.primaryVideoContainer.leadingAnchor),
                        renderer.videoView.trailingAnchor.constraint(equalTo: self.primaryVideoContainer.trailingAnchor),
                        renderer.videoView.topAnchor.constraint(equalTo: self.primaryVideoContainer.topAnchor),
                        renderer.videoView.bottomAnchor.constraint(equalTo: self.primaryVideoContainer.bottomAnchor)
                    ])

                    // Force layout pass IMMEDIATELY
                    self.primaryVideoContainer.layoutIfNeeded()
                    renderer.videoView.layoutIfNeeded()

                    print("✅ Moved focused renderer to primary container: \(participantIdentity) (frame: \(renderer.videoView.frame))")
                }
            } else {
                // Should be in thumbnail grid
                if renderer.videoView.superview != self.thumbnailGridContainer {
                    // Critical: Remove from current superview BEFORE adding to new parent
                    renderer.videoView.removeFromSuperview()
                    self.thumbnailGridContainer.addArrangedSubview(renderer.videoView)
                    NSLayoutConstraint.activate([
                        renderer.videoView.heightAnchor.constraint(equalToConstant: 120)
                    ])
                    print("✅ Moved renderer to thumbnail grid: \(participantIdentity)")
                }
            }

            print("✅ Added video track to participant: \(participantIdentity) (focused: \(renderer.isFocused))")
        }
    }

    private func removeRemoteVideoTrack(_ participantIdentity: String, track: RemoteVideoTrack) {
        guard var renderer = participantRenderers[participantIdentity] else {
            print("No renderer found for participant: \(participantIdentity)")
            return
        }

        DispatchQueue.main.async {
            track.removeRenderer(renderer.videoView)

            // Clear track reference
            renderer.videoTrack = nil
            self.participantRenderers[participantIdentity] = renderer

            print("Removed video track from participant: \(participantIdentity)")
        }
    }

    private func updateDominantSpeaker(_ participantIdentity: String?) {
        dominantSpeakerIdentity = participantIdentity

        // Only auto-focus on dominant speaker if user hasn't made a selection
        if !userHasSelectedParticipant, let identity = participantIdentity,
           participantRenderers.keys.contains(identity) {
            updateFocusedParticipant(identity, isUserSelection: false)
        }
    }
}

// MARK: - Remote Participant Delegate
extension VideoCallViewController: RemoteParticipantDelegate {
    func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print("Participant \(participant.identity) published video track")
    }

    func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print("Participant \(participant.identity) unpublished video track")
    }

    func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print("Participant \(participant.identity) published audio track")
    }

    func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print("Participant \(participant.identity) unpublished audio track")
    }

    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        print("🎥 Subscribed to video track for participant \(participant.identity)")
        // Critical: Only add track if participant renderer exists and track not already attached
        if let renderer = participantRenderers[participant.identity] {
            if renderer.videoTrack == nil {
                addRemoteVideoTrack(participant.identity, track: videoTrack)
            } else {
                print("⚠️ Track already attached to \(participant.identity), skipping")
            }
        } else {
            print("⚠️ No renderer found for \(participant.identity)")
        }
    }

    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        print("Unsubscribed from video track for participant \(participant.identity)")
        removeRemoteVideoTrack(participant.identity, track: videoTrack)
    }

    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        print("Subscribed to audio track for participant \(participant.identity)")
    }

    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        print("Unsubscribed from audio track for participant \(participant.identity)")
    }

    func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print("Participant \(participant.identity) enabled video track")
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print("Participant \(participant.identity) disabled video track")
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print("Participant \(participant.identity) enabled audio track")
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print("Participant \(participant.identity) disabled audio track")
    }

    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        print("Failed to subscribe to audio track: \(error.localizedDescription)")
    }

    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        print("Failed to subscribe to video track: \(error.localizedDescription)")
    }

    func remoteParticipantNetworkQualityLevelDidChange(participant: RemoteParticipant, networkQualityLevel: NetworkQualityLevel) {
        TwilioVideoPlugin.getInstance()?.notifyNetworkQualityChanged(
            identity: participant.identity,
            level: networkQualityLevel.rawValue,
            isLocal: false
        )
    }
}

// MARK: - Camera Source Delegate
extension VideoCallViewController: CameraSourceDelegate {
    func cameraSourceDidFail(source: CameraSource, error: Error) {
        print("Camera source failed: \(error.localizedDescription)")
    }
}
