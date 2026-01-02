import UIKit
import TwilioVideo
import AVFoundation

class VideoCallViewController: UIViewController {

    // MARK: - Properties
    var accessToken: String?
    var roomName: String?

    private var room: Room?
    private var localParticipant: LocalParticipant?
    private var localVideoTrack: LocalVideoTrack?
    private var localAudioTrack: LocalAudioTrack?
    private var camera: CameraSource?
    private var remoteParticipantCount = 0

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

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        setupFullScreenUI()
        setupLocalMedia()
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
        button.backgroundColor = .systemGray
        button.layer.cornerRadius = 24
        button.translatesAutoresizingMaskIntoConstraints = false

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
            camera.startCapture(device: frontCamera()) { (captureDevice, videoFormat, error) in
                if let error = error {
                    print("Camera start capture failed: \(error.localizedDescription)")
                }
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
        isAudioMuted = muted
        localAudioTrack?.isEnabled = !muted
    }

    func enableVideo(enabled: Bool) {
        isVideoEnabled = enabled
        localVideoTrack?.isEnabled = enabled
    }

    @objc func flipCamera() {
        guard let camera = camera else { return }

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
    }

    @objc func disconnect() {
        room?.disconnect()
        cleanup()
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Cleanup
    private func cleanup() {
        localVideoTrack?.removeRenderer(thumbnailVideoView)
        localVideoTrack = nil
        localAudioTrack = nil
        camera?.stopCapture()
        camera = nil
        room = nil
        localParticipant = nil
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
}

// MARK: - Room Delegate
extension VideoCallViewController: RoomDelegate {
    func roomDidConnect(room: Room) {
        print("Connected to room: \(room.name)")
        localParticipant = room.localParticipant

        TwilioVideoPlugin.getInstance()?.notifyRoomConnected(roomName: room.name)

        // Handle existing participants
        for participant in room.remoteParticipants {
            addRemoteParticipant(participant)
        }
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        print("Failed to connect to room: \(error.localizedDescription)")
        TwilioVideoPlugin.getInstance()?.notifyRoomError(
            code: "CONNECT_FAILED",
            message: error.localizedDescription,
            isFatal: true
        )
        dismiss(animated: true, completion: nil)
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        print("Disconnected from room: \(room.name)")
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
        TwilioVideoPlugin.getInstance()?.notifyDominantSpeakerChanged(identity: participant?.identity)
    }
}

// MARK: - Remote Participant Management
extension VideoCallViewController {
    private func addRemoteParticipant(_ participant: RemoteParticipant) {
        remoteParticipantCount += 1
        participant.delegate = self

        // Subscribe to existing video tracks
        for publication in participant.remoteVideoTracks {
            if let track = publication.remoteTrack, publication.isTrackSubscribed {
                addRemoteVideoTrack(track)
            }
        }
    }

    private func removeRemoteParticipant(_ participant: RemoteParticipant) {
        remoteParticipantCount -= 1

        for publication in participant.remoteVideoTracks {
            if let track = publication.remoteTrack, publication.isTrackSubscribed {
                removeRemoteVideoTrack(track)
            }
        }
    }

    private func addRemoteVideoTrack(_ track: RemoteVideoTrack) {
        DispatchQueue.main.async {
            track.addRenderer(self.primaryVideoView)
        }
    }

    private func removeRemoteVideoTrack(_ track: RemoteVideoTrack) {
        DispatchQueue.main.async {
            track.removeRenderer(self.primaryVideoView)
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
        addRemoteVideoTrack(videoTrack)
    }

    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        print("Unsubscribed from video track for participant \(participant.identity)")
        removeRemoteVideoTrack(videoTrack)
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
