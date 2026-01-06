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
    private var primaryVideoView: VideoView!
    private var thumbnailVideoView: VideoView!
    private var controlsContainer: UIView!
    private var muteButton: UIButton!
    private var videoButton: UIButton!
    private var flipButton: UIButton!
    private var speakerButton: UIButton!
    private var hangupButton: UIButton!

    // State
    private var isAudioMuted = false
    private var isVideoEnabled = true
    private var isSpeakerEnabled = true

    // Multi-participant video management
    private var participantVideoViews: [String: VideoView] = [:]
    private var dominantSpeakerIdentity: String?
    private var dominantSpeakerDebounceTimer: Timer?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        setupFullScreenUI()
        setupLocalMedia()

        // Transition to joining state
        transitionToState(.joining)
        connectToRoom()
    }

    // MARK: - UI Setup
    private func setupFullScreenUI() {
        view.backgroundColor = .black

        // Primary video view (remote participant - full screen)
        primaryVideoView = VideoView(frame: view.bounds)
        primaryVideoView.contentMode = .scaleAspectFill
        primaryVideoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(primaryVideoView)

        // Thumbnail video view (local participant - picture-in-picture)
        let thumbnailSize: CGFloat = 120
        let thumbnailFrame = CGRect(x: view.bounds.width - thumbnailSize - 16,
                                   y: 50,
                                   width: thumbnailSize,
                                   height: thumbnailSize)
        thumbnailVideoView = VideoView(frame: thumbnailFrame)
        thumbnailVideoView.contentMode = .scaleAspectFill
        thumbnailVideoView.backgroundColor = .darkGray
        thumbnailVideoView.layer.cornerRadius = 8
        thumbnailVideoView.clipsToBounds = true
        thumbnailVideoView.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        view.addSubview(thumbnailVideoView)

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

        setupControls()
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

        muteButton = createControlButton(title: "🎤")
        muteButton.addTarget(self, action: #selector(toggleAudioMute), for: .touchUpInside)

        videoButton = createControlButton(title: "📹")
        videoButton.addTarget(self, action: #selector(toggleVideo), for: .touchUpInside)

        flipButton = createControlButton(title: "🔄")
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)

        speakerButton = createControlButton(title: "🔊")
        speakerButton.addTarget(self, action: #selector(toggleSpeaker), for: .touchUpInside)

        hangupButton = createControlButton(title: "📞")
        hangupButton.backgroundColor = .systemRed
        hangupButton.addTarget(self, action: #selector(disconnect), for: .touchUpInside)

        stackView.addArrangedSubview(muteButton)
        stackView.addArrangedSubview(videoButton)
        stackView.addArrangedSubview(flipButton)
        stackView.addArrangedSubview(speakerButton)
        stackView.addArrangedSubview(hangupButton)
    }

    private func createControlButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        button.layer.cornerRadius = 24
        button.translatesAutoresizingMaskIntoConstraints = false

        // Set up stateful colors
        button.backgroundColor = .systemGray
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.lightGray, for: .disabled)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        return button
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
            if let renderer = thumbnailVideoView {
                localVideoTrack?.addRenderer(renderer)
            }

            // Start camera
            if let device = frontCamera() {
                camera.startCapture(device: device) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        print("Camera start capture failed: \(error.localizedDescription)")
                    }
                }
            } else {
                print("Failed to get front camera device")
            }
        }

        // Configure audio session for VoIP
        configureAudioSession()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetooth])
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
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

        isAudioMuted = muted
        localAudioTrack?.isEnabled = !muted
        updateButtonStates()
    }

    func enableVideo(enabled: Bool) {
        guard callState == .connected else {
            print("Cannot toggle video, not connected. State: \(callState)")
            return
        }

        isVideoEnabled = enabled
        localVideoTrack?.isEnabled = enabled
        updateButtonStates()
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
                }
            }
        }
    }

    func setSpeaker(enabled: Bool) {
        guard callState == .connected else {
            print("Cannot toggle speaker, not connected. State: \(callState)")
            return
        }

        isSpeakerEnabled = enabled
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if enabled {
                try audioSession.overrideOutputAudioPort(.speaker)
            } else {
                try audioSession.overrideOutputAudioPort(.none)
            }
        } catch {
            print("Failed to set speaker: \(error.localizedDescription)")
        }
        updateButtonStates()
    }

    @objc func disconnect() {
        guard callState != .disconnecting && callState != .disconnected else {
            print("Already disconnecting or disconnected, ignoring")
            return
        }

        transitionToState(.disconnecting)
        room?.disconnect()
        cleanup()
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Cleanup
    private func cleanup() {
        // Cancel any pending dominant speaker updates
        dominantSpeakerDebounceTimer?.invalidate()
        dominantSpeakerDebounceTimer = nil

        localVideoTrack?.removeRenderer(thumbnailVideoView)
        localVideoTrack = nil
        localAudioTrack = nil
        camera?.stopCapture()
        camera = nil
        room = nil
        localParticipant = nil

        // Clean up all participant video views
        participantVideoViews.removeAll()
        dominantSpeakerIdentity = nil
    }

    deinit {
        cleanup()
    }

    // MARK: - Auto-Close Logic
    private func checkAutoClose() {
        if remoteParticipantCount == 0 {
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
            // Mute button
            self.muteButton.isEnabled = isConnected
            self.muteButton.backgroundColor = self.isAudioMuted ? .systemGreen : .systemGray
            self.muteButton.alpha = isConnected ? 1.0 : 0.5

            // Video button
            self.videoButton.isEnabled = isConnected
            self.videoButton.backgroundColor = self.isVideoEnabled ? .systemGray : .systemGreen
            self.videoButton.alpha = isConnected ? 1.0 : 0.5

            // Flip button
            self.flipButton.isEnabled = isConnected && self.isVideoEnabled
            self.flipButton.alpha = (isConnected && self.isVideoEnabled) ? 1.0 : 0.5

            // Speaker button
            self.speakerButton.isEnabled = isConnected
            self.speakerButton.backgroundColor = self.isSpeakerEnabled ? .systemGreen : .systemGray
            self.speakerButton.alpha = isConnected ? 1.0 : 0.5

            // Hangup button - always enabled once joining
            self.hangupButton.isEnabled = (self.callState == .joining ||
                                          self.callState == .connected)
            self.hangupButton.alpha = self.hangupButton.isEnabled ? 1.0 : 0.5
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

        // Create or get stable video view for this participant
        let videoView = participantVideoViews[participant.identity] ?? {
            let view = VideoView(frame: .zero)
            view.contentMode = .scaleAspectFill
            participantVideoViews[participant.identity] = view
            print("Created new VideoView for participant: \(participant.identity)")
            return view
        }()

        // Subscribe to existing video tracks
        for publication in participant.remoteVideoTracks {
            if let track = publication.remoteTrack, publication.isTrackSubscribed {
                addRemoteVideoTrack(participant.identity, track: track)
            }
        }
    }

    private func removeRemoteParticipant(_ participant: RemoteParticipant) {
        remoteParticipantCount -= 1

        for publication in participant.remoteVideoTracks {
            if let track = publication.remoteTrack, publication.isTrackSubscribed {
                removeRemoteVideoTrack(participant.identity, track: track)
            }
        }

        // Clean up video view for this participant
        if let videoView = participantVideoViews.removeValue(forKey: participant.identity) {
            DispatchQueue.main.async {
                if videoView.superview == self.primaryVideoView {
                    videoView.removeFromSuperview()
                }
            }
            print("Removed VideoView for participant: \(participant.identity)")
        }
    }

    private func addRemoteVideoTrack(_ participantIdentity: String, track: RemoteVideoTrack) {
        guard let videoView = participantVideoViews[participantIdentity] else {
            print("No VideoView found for participant: \(participantIdentity)")
            return
        }

        DispatchQueue.main.async {
            // Add renderer to the stable video view (reuse, don't recreate)
            track.addRenderer(videoView)

            // If this is the dominant speaker or first participant, show in primary view
            if self.dominantSpeakerIdentity == participantIdentity || self.remoteParticipantCount == 1 {
                self.updatePrimaryVideoView(participantIdentity)
            }

            print("Added video track renderer for participant: \(participantIdentity)")
        }
    }

    private func removeRemoteVideoTrack(_ participantIdentity: String, track: RemoteVideoTrack) {
        guard let videoView = participantVideoViews[participantIdentity] else {
            print("No VideoView found for participant: \(participantIdentity)")
            return
        }

        DispatchQueue.main.async {
            track.removeRenderer(videoView)
            print("Removed video track renderer for participant: \(participantIdentity)")
        }
    }

    private func updateDominantSpeaker(_ participantIdentity: String?) {
        dominantSpeakerIdentity = participantIdentity

        if let identity = participantIdentity {
            updatePrimaryVideoView(identity)
        }
    }

    private func updatePrimaryVideoView(_ participantIdentity: String) {
        guard let videoView = participantVideoViews[participantIdentity] else { return }

        DispatchQueue.main.async {
            // Only update if not already showing this participant
            if self.primaryVideoView.subviews.first != videoView {
                // Remove all existing subviews
                self.primaryVideoView.subviews.forEach { $0.removeFromSuperview() }

                // Add the participant's video view
                videoView.frame = self.primaryVideoView.bounds
                videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.primaryVideoView.addSubview(videoView)

                print("Updated primary view to show participant: \(participantIdentity)")
            }
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
        print("Subscribed to video track for participant \(participant.identity)")
        addRemoteVideoTrack(participant.identity, track: videoTrack)
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
