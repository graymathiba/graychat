import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/app_config.dart';
import '../utils/app_logger.dart';

enum CallState {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  active,
  ended,
}

enum CallType { audio, video }

class CallInfo {
  final String peerId;
  final String peerName;
  final CallType callType;
  final CallState state;
  final Duration duration;

  const CallInfo({
    required this.peerId,
    required this.peerName,
    required this.callType,
    required this.state,
    this.duration = Duration.zero,
  });
}

class CallService {
  final io.Socket _socket;
  final String localUserId;
  String localDisplayName = '';

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  CallState _state = CallState.idle;
  CallType _callType = CallType.audio;
  String _remotePeerId = '';
  String _remotePeerName = '';
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;

  final _callInfoController = StreamController<CallInfo?>.broadcast();
  final _videoStateController = StreamController<void>.broadcast();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _localRendererInitialized = false;
  bool _remoteRendererInitialized = false;

  Stream<CallInfo?> get callInfoStream => _callInfoController.stream;
  Stream<void> get videoStateStream => _videoStateController.stream;
  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  CallState get state => _state;
  CallType get callType => _callType;
  String get remotePeerId => _remotePeerId;

  CallService({required this._socket, required this.localUserId}) {
    _listenForCallSignals();
  }

  void _updateState(CallState newState) {
    _state = newState;
    _emitCallInfo();
  }

  void _emitCallInfo() {
    if (_state == CallState.idle) {
      _callInfoController.add(null);
    } else {
      _callInfoController.add(
        CallInfo(
          peerId: _remotePeerId,
          peerName: _remotePeerName,
          callType: _callType,
          state: _state,
          duration: _callDuration,
        ),
      );
    }
  }

  void _emitVideoState() {
    _videoStateController.add(null);
  }

  void _setupPeerCallbacks(RTCPeerConnection pc, {bool isIncoming = false}) {
    final tag = isIncoming ? 'incoming' : 'outgoing';

    pc.onTrack = (event) {
      if (_state == CallState.idle || _state == CallState.ended) return;
      AppLogger.success('CallService', 'onTrack ($tag)', {
        'streams': event.streams.length,
        'trackKind': event.track.kind,
      });
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteRenderer.srcObject = _remoteStream;
        _emitVideoState();
      }
    };

    pc.onIceCandidate = (candidate) {
      _socket.emit('call:ice_candidate', {
        'targetId': _remotePeerId,
        'data': {'candidate': candidate.toMap()},
      });
    };

    pc.onIceConnectionState = (RTCIceConnectionState iceState) {
      AppLogger.info('CallService', 'ICE state ($tag)', {
        'state': iceState.name,
      });
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (_state != CallState.active &&
            _state != CallState.idle &&
            _state != CallState.ended) {
          _startDurationTimer();
          _updateState(CallState.active);
          _emitVideoState();
        }
      } else if (iceState ==
              RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        if (_state != CallState.idle && _state != CallState.ended) {
          endCall();
        }
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      AppLogger.info('CallService', 'Peer state ($tag)', {'state': state.name});
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_state != CallState.idle && _state != CallState.ended) {
          endCall();
        }
      }
    };
  }

  void _listenForCallSignals() {
    _socket.on('call:offer', (data) async {
      final senderId = data['senderId'] as String;
      final inner = data['data'] as Map<String, dynamic>;
      final offer = inner['offer'] as Map<String, dynamic>;
      final callerName = inner['callerName'] as String? ?? 'Unknown';
      final callTypeStr = inner['callType'] as String? ?? 'audio';

      AppLogger.info('CallService', 'Incoming call', {
        'from': callerName,
        'type': callTypeStr,
      });

      _remotePeerId = senderId;
      _remotePeerName = callerName;
      _callType = callTypeStr == 'video' ? CallType.video : CallType.audio;
      _updateState(CallState.incomingRinging);

      await _setupLocalMedia();
      _peerConnection = await createPeerConnection(AppConfig.iceServers);
      _setupPeerCallbacks(_peerConnection!, isIncoming: true);

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
    });

    _socket.on('call:answer', (data) async {
      final inner = data['data'] as Map<String, dynamic>;
      final answer = inner['answer'] as Map<String, dynamic>;
      AppLogger.info(
        'CallService',
        'Answer received — setting remote desc',
        {},
      );
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });

    _socket.on('call:reject', (data) {
      AppLogger.info('CallService', 'Call rejected', data);
      _updateState(CallState.ended);
      _cleanup();
      _scheduleIdleTimeout();
    });

    _socket.on('call:hangup', (data) {
      AppLogger.info('CallService', 'Call hung up', data);
      _updateState(CallState.ended);
      _cleanup();
      _scheduleIdleTimeout();
    });

    _socket.on('call:ice_candidate', (data) async {
      final inner = data['data'] as Map<String, dynamic>?;
      final candidate = inner?['candidate'] as Map<String, dynamic>?;
      if (candidate != null && _peerConnection != null) {
        AppLogger.info('CallService', 'Received ICE candidate', {
          'sdpMid': candidate['sdpMid'],
        });
        await _peerConnection!.addCandidate(
          RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ),
        );
      }
    });
  }

  Future<void> _setupLocalMedia() async {
    if (_localStream != null) return;

    final constraints = <String, dynamic>{
      'audio': true,
      'video': _callType == CallType.video
          ? {'width': 640, 'height': 480, 'frameRate': 30}
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (e) {
      AppLogger.error('CallService', 'getUserMedia failed', e);
    }

    if (!_localRendererInitialized) {
      await _localRenderer.initialize();
      _localRendererInitialized = true;
    }
    _localRenderer.srcObject = _localStream;

    if (!_remoteRendererInitialized) {
      await _remoteRenderer.initialize();
      _remoteRendererInitialized = true;
    }
  }

  Future<void> startCall(String peerId, String peerName, CallType type) async {
    if (_state != CallState.idle) return;

    _remotePeerId = peerId;
    _remotePeerName = peerName;
    _callType = type;
    _updateState(CallState.outgoingRinging);

    await _setupLocalMedia();
    _peerConnection = await createPeerConnection(AppConfig.iceServers);
    _setupPeerCallbacks(_peerConnection!, isIncoming: false);

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    AppLogger.info('CallService', 'Sending offer', {'target': _remotePeerId});
    _socket.emit('call:offer', {
      'targetId': _remotePeerId,
      'data': {
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'callerName': localDisplayName.isNotEmpty
            ? localDisplayName
            : localUserId,
        'callType': type == CallType.video ? 'video' : 'audio',
      },
    });
  }

  Future<void> answerCall() async {
    if (_state != CallState.incomingRinging) return;

    _updateState(CallState.connecting);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    AppLogger.info('CallService', 'Sending answer', {'target': _remotePeerId});
    _socket.emit('call:answer', {
      'targetId': _remotePeerId,
      'data': {
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      },
    });
  }

  void rejectCall() {
    if (_state != CallState.incomingRinging) return;
    _socket.emit('call:reject', {'targetId': _remotePeerId, 'data': {}});
    _updateState(CallState.ended);
    _cleanup();
    _scheduleIdleTimeout();
  }

  void endCall() {
    if (_state == CallState.idle || _state == CallState.ended) return;
    if (_remotePeerId.isNotEmpty) {
      _socket.emit('call:hangup', {'targetId': _remotePeerId, 'data': {}});
    }
    _updateState(CallState.ended);
    _cleanup();
    _scheduleIdleTimeout();
  }

  void _scheduleIdleTimeout() {
    Future.delayed(const Duration(seconds: 2), () {
      if (_state == CallState.ended) _updateState(CallState.idle);
    });
  }

  Future<void> toggleMute() async {
    if (_localStream == null) return;
    for (final audioTrack in _localStream!.getAudioTracks()) {
      audioTrack.enabled = !audioTrack.enabled;
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null || _callType != CallType.video) return;
    for (final videoTrack in _localStream!.getVideoTracks()) {
      videoTrack.enabled = !videoTrack.enabled;
    }
  }

  Future<void> toggleCameraFacing() async {
    if (_localStream == null || _callType != CallType.video) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack == null) return;
    await Helper.switchCamera(videoTrack);
  }

  bool get isMuted {
    if (_localStream == null) return false;
    final audioTracks = _localStream!.getAudioTracks();
    return audioTracks.isNotEmpty && !audioTracks.first.enabled;
  }

  bool get isCameraOff {
    if (_localStream == null || _callType != CallType.video) return false;
    final videoTracks = _localStream!.getVideoTracks();
    return videoTracks.isNotEmpty && !videoTracks.first.enabled;
  }

  void _startDurationTimer() {
    _callDuration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration += const Duration(seconds: 1);
      _emitCallInfo();
    });
  }

  void _cleanup() {
    try {
      _durationTimer?.cancel();
      _durationTimer = null;
      _callDuration = Duration.zero;

      // 1. Detach streams from renderers first (stops the video surface)
      try {
        _localRenderer.srcObject = null;
        _remoteRenderer.srcObject = null;
      } catch (_) {}

      // 2. Stop local tracks
      try {
        _localStream?.getTracks().forEach((track) {
          try { track.stop(); } catch (_) {}
        });
      } catch (_) {}

      // 3. Close peer connection
      try { _peerConnection?.close(); } catch (_) {}

      // 4. Null all references
      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;
      _remotePeerId = '';
      _remotePeerName = '';
    } catch (e) {
      AppLogger.error('CallService', 'Error during cleanup', e);
    }
  }

  void dispose() {
    _cleanup();
    _durationTimer?.cancel();
    try {
      _localRenderer.dispose();
      _remoteRenderer.dispose();
    } catch (_) {}
    _localRendererInitialized = false;
    _remoteRendererInitialized = false;
    _callInfoController.close();
    _videoStateController.close();
  }
}
