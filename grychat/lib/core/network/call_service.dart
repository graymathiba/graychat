import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/app_logger.dart';

enum CallState { idle, outgoingRinging, incomingRinging, connecting, active, ended }

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
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _localRendererInitialized = false;
  bool _remoteRendererInitialized = false;

  Stream<CallInfo?> get callInfoStream => _callInfoController.stream;
  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  CallState get state => _state;
  CallType get callType => _callType;
  String get remotePeerId => _remotePeerId;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

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
      _callInfoController.add(CallInfo(
        peerId: _remotePeerId,
        peerName: _remotePeerName,
        callType: _callType,
        state: _state,
        duration: _callDuration,
      ));
    }
  }

  void _listenForCallSignals() {
    _socket.on('call_offer', (data) async {
      final callerId = data['callerId'] as String;
      final callerName = data['callerName'] as String? ?? 'Unknown';
      final offer = data['offer'];
      final callTypeStr = data['callType'] as String? ?? 'audio';

      AppLogger.info('CallService', 'Incoming call', {
        'from': callerName,
        'type': callTypeStr,
      });

      _remotePeerId = callerId;
      _remotePeerName = callerName;
      _callType = callTypeStr == 'video' ? CallType.video : CallType.audio;
      _updateState(CallState.incomingRinging);

      // Pre-setup peer connection and tracks for quick answer
      await _setupLocalMedia();
      _peerConnection = await createPeerConnection(_iceServers);

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        _socket.emit('call_ice_candidate', {
          'receiverId': _remotePeerId,
          'candidate': candidate.toMap(),
        });
      };

      _peerConnection!.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          endCall();
        }
      };

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
    });

    _socket.on('call_answer', (data) async {
      final answer = data['answer'];
      AppLogger.info('CallService', 'Call answered', {});
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
      _startDurationTimer();
      _updateState(CallState.active);
    });

    _socket.on('call_reject', (data) {
      AppLogger.info('CallService', 'Call rejected', data);
      _cleanup();
      _updateState(CallState.ended);
      Future.delayed(const Duration(seconds: 2), () {
        if (_state == CallState.ended) _updateState(CallState.idle);
      });
    });

    _socket.on('call_hangup', (data) {
      AppLogger.info('CallService', 'Call hung up', data);
      _cleanup();
      _updateState(CallState.ended);
      Future.delayed(const Duration(seconds: 2), () {
        if (_state == CallState.ended) _updateState(CallState.idle);
      });
    });

    _socket.on('call_ice_candidate', (data) async {
      final candidate = data['candidate'];
      if (candidate != null && _peerConnection != null) {
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

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);

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
    _peerConnection = await createPeerConnection(_iceServers);

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteRenderer.srcObject = _remoteStream;
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      _socket.emit('call_ice_candidate', {
        'receiverId': _remotePeerId,
        'candidate': candidate.toMap(),
      });
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        endCall();
      }
    };

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _socket.emit('call_offer', {
      'receiverId': _remotePeerId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'callType': type == CallType.video ? 'video' : 'audio',
    });
  }

  Future<void> answerCall() async {
    if (_state != CallState.incomingRinging) return;

    _updateState(CallState.connecting);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _socket.emit('call_answer', {
      'callerId': _remotePeerId,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });

    _startDurationTimer();
    _updateState(CallState.active);
  }

  void rejectCall() {
    if (_state != CallState.incomingRinging) return;
    _socket.emit('call_reject', {'callerId': _remotePeerId});
    _cleanup();
    _updateState(CallState.ended);
    Future.delayed(const Duration(seconds: 1), () {
      if (_state == CallState.ended) _updateState(CallState.idle);
    });
  }

  void endCall() {
    _socket.emit('call_hangup', {'receiverId': _remotePeerId});
    _cleanup();
    _updateState(CallState.ended);
    Future.delayed(const Duration(seconds: 1), () {
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
    _durationTimer?.cancel();
    _durationTimer = null;
    _callDuration = Duration.zero;

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    _remoteStream = null;

    _peerConnection?.close();
    _peerConnection = null;

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    _remotePeerId = '';
    _remotePeerName = '';
  }

  void dispose() {
    _cleanup();
    _durationTimer?.cancel();
    _callInfoController.close();
  }
}
