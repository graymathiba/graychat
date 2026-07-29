import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../database/database_service.dart';
import '../database/models.dart';
import 'signaling_service.dart';

class PeerConnectionStateUpdate {
  final String peerId;
  final String state; // 'connecting', 'connected', 'disconnected'

  PeerConnectionStateUpdate(this.peerId, this.state);
}

class WebRTCService {
  final SignalingService _signalingService;
  final DatabaseService _databaseService;

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Map<String, String> _connectionStates = {};
  final Map<String, String> _activeInboundFileIds = {};
  final Map<String, InboundFileTransfer> _inboundTransfers = {};

  StreamSubscription? _signalingSubscription;

  final StreamController<PeerConnectionStateUpdate> _connectionStateController =
      StreamController<PeerConnectionStateUpdate>.broadcast();

  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      }
    ]
  };

  WebRTCService(this._signalingService, this._databaseService) {
    _initialize();
  }

  /// Broadcasts peer connection state transitions
  Stream<PeerConnectionStateUpdate> get connectionStateStream =>
      _connectionStateController.stream;

  /// Gets the current connection state of a specific peer
  String getConnectionState(String peerId) {
    return _connectionStates[peerId] ?? 'disconnected';
  }

  /// Initialize signaling event listeners
  void _initialize() {
    _signalingSubscription = _signalingService.signalStream.listen(
      (envelope) {
        _handleSignalingMessage(envelope);
      },
      onError: (e) {
        print('[WebRTCService] Signaling stream error: $e');
      },
    );
  }

  /// Routes incoming signaling events
  void _handleSignalingMessage(Map<String, dynamic> envelope) async {
    final senderId = envelope['senderId'] as String?;
    final targetId = envelope['targetId'] as String?;
    final type = envelope['type'] as String?;
    final data = envelope['data'] as Map<String, dynamic>?;

    // Verify signal envelope validity and destination matching
    if (senderId == null || targetId != _signalingService.localPeerId || data == null) {
      return;
    }

    print('[WebRTCService] Received signaling event "$type" from peer $senderId');

    switch (type) {
      case 'offer':
        await _handleOffer(senderId, data);
        break;
      case 'answer':
        await _handleAnswer(senderId, data);
        break;
      case 'ice_candidate':
        await _handleIceCandidate(senderId, data);
        break;
      default:
        print('[WebRTCService] Unknown signaling type: $type');
    }
  }

  /// Connects to a target peer as the initiator
  Future<void> connectToPeer(String peerId) async {
    try {
      print('[WebRTCService] Initiating WebRTC handshake with $peerId...');
      _updateConnectionState(peerId, 'connecting');
      final pc = await _getOrCreatePeerConnection(peerId);

      // Create P2P Data Channel for real-time text/file synchronization
      final init = RTCDataChannelInit()..ordered = true;
      final dc = await pc.createDataChannel('chat_channel', init);
      _registerDataChannelHandlers(peerId, dc);

      // Create and set local session description (SDP Offer)
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Transport the offer to the peer via Socket.io
      // Use a room based on sorted peer IDs to ensure both peers use same room
      final roomId = _generateRoomId(peerId);
      _signalingService.joinRoom(roomId);
      _signalingService.sendOffer(roomId, {
        'sdp': offer.sdp,
        'type': 'offer',
      });
    } catch (e) {
      print('[WebRTCService] Error initiating connection to $peerId: $e');
      _updateConnectionState(peerId, 'disconnected');
    }
  }

  /// Generate a consistent room ID for two peers
  String _generateRoomId(String peerId) {
    final ids = [_signalingService.localPeerId, peerId];
    ids.sort();
    return ids.join('_');
  }

  /// Sets remote SDP offer, generates SDP answer, and sends it back
  Future<void> _handleOffer(String peerId, Map<String, dynamic> data) async {
    try {
      final sdp = data['sdp'] as String?;
      if (sdp == null) return;

      _updateConnectionState(peerId, 'connecting');
      final pc = await _getOrCreatePeerConnection(peerId);

      // Set the incoming offer as the remote description
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

      // Generate local description (SDP Answer)
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      // Transport the answer back via Socket.io
      final roomId = _generateRoomId(peerId);
      _signalingService.joinRoom(roomId);
      _signalingService.sendAnswer(roomId, {
        'sdp': answer.sdp,
        'type': 'answer',
      });
    } catch (e) {
      print('[WebRTCService] Error handling offer from $peerId: $e');
      _updateConnectionState(peerId, 'disconnected');
    }
  }

  /// Sets remote SDP answer on the initiator peer connection
  Future<void> _handleAnswer(String peerId, Map<String, dynamic> data) async {
    try {
      final sdp = data['sdp'] as String?;
      if (sdp == null) return;

      final pc = _peerConnections[peerId];
      if (pc == null) {
        print('[WebRTCService] Answer received for non-existent connection: $peerId');
        return;
      }

      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    } catch (e) {
      print('[WebRTCService] Error handling answer from $peerId: $e');
      _updateConnectionState(peerId, 'disconnected');
    }
  }

  /// Adds ICE candidate to the peer connection
  Future<void> _handleIceCandidate(String peerId, Map<String, dynamic> data) async {
    try {
      final candidate = data['candidate'] as String?;
      final sdpMid = data['sdpMid'] as String?;
      final sdpMLineIndex = data['sdpMLineIndex'] as int?;

      if (candidate == null) return;

      final pc = _peerConnections[peerId];
      if (pc == null) {
        print('[WebRTCService] ICE Candidate received for non-existent connection: $peerId');
        return;
      }

      await pc.addCandidate(RTCIceCandidate(candidate, sdpMid, sdpMLineIndex));
    } catch (e) {
      print('[WebRTCService] Error adding ICE candidate from $peerId: $e');
    }
  }

  /// Generates a connection or returns cached one for a peer
  Future<RTCPeerConnection> _getOrCreatePeerConnection(String peerId) async {
    if (_peerConnections.containsKey(peerId)) {
      return _peerConnections[peerId]!;
    }

    final pc = await createPeerConnection(_iceConfiguration);
    _peerConnections[peerId] = pc;

    // Send gathered ICE candidates via Socket.io
    pc.onIceCandidate = (candidate) {
      final roomId = _generateRoomId(peerId);
      _signalingService.sendIceCandidate(roomId, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Listen to network status drops or close events
    pc.onIceConnectionState = (state) {
      print('[WebRTCService] ICE Connection state change for $peerId: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _updateConnectionState(peerId, 'disconnected');
        _cleanupPeerResources(peerId);
      }
    };

    // Received data channel callback (for receivers)
    pc.onDataChannel = (channel) {
      print('[WebRTCService] Incoming Data Channel established from $peerId');
      _registerDataChannelHandlers(peerId, channel);
    };

    return pc;
  }

  /// Attaches listeners to track connection state and routing payloads
  void _registerDataChannelHandlers(String peerId, RTCDataChannel channel) {
    _dataChannels[peerId] = channel;

    channel.onDataChannelState = (state) {
      print('[WebRTCService] Data Channel state change for $peerId: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _updateConnectionState(peerId, 'connected');
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _updateConnectionState(peerId, 'disconnected');
        _cleanupPeerResources(peerId);
      }
    };

    channel.onMessage = (message) {
      _handleIncomingMessage(peerId, message);
    };
  }

  /// Receives message payload from data channel and saves it to Hive DB
  void _handleIncomingMessage(String peerId, RTCDataChannelMessage message) async {
    try {
      if (message.isBinary) {
        print('[WebRTCService] Received P2P binary chunk from $peerId (${message.binary.length} bytes)');
        final fileId = _activeInboundFileIds[peerId];
        if (fileId != null && _inboundTransfers.containsKey(fileId)) {
          final transfer = _inboundTransfers[fileId]!;
          transfer.chunks.add(message.binary);
          transfer.bytesTransferred += message.binary.length;

          final progress = transfer.fileSize > 0
              ? transfer.bytesTransferred / transfer.fileSize
              : 0.0;

          // Update local Database MessageModel
          final existingMsg = _databaseService.getMessageById(fileId);
          if (existingMsg != null) {
            final isComplete = transfer.bytesTransferred >= transfer.fileSize || transfer.chunks.length >= transfer.chunkCount;
            
            final updatedMsg = existingMsg.copyWith(
              bytesTransferred: transfer.bytesTransferred,
              fileProgress: isComplete ? 1.0 : progress,
              isTransferComplete: isComplete,
            );
            await _databaseService.updateMessage(updatedMsg);

            // If completed, write to storage
            if (isComplete) {
              await _saveAssembledFile(transfer);
              _inboundTransfers.remove(fileId);
              if (_activeInboundFileIds[peerId] == fileId) {
                _activeInboundFileIds.remove(peerId);
              }
            }
          }
        }
      } else {
        final text = message.text;
        print('[WebRTCService] Received P2P message text from $peerId: $text');

        // Parse serialized MessageModel JSON payload
        final Map<String, dynamic> json = jsonDecode(text);

        // Check if this is a file transfer initialization packet
        if (json.containsKey('type') && json['type'] == 'FILE_INIT') {
          final fileId = json['fileId'] as String;
          final fileName = json['fileName'] as String;
          final fileSize = json['fileSize'] as int;
          final chunkCount = json['chunkCount'] as int;
          final senderId = json['senderId'] as String;

          // Set active inbound file for this remote peer
          _activeInboundFileIds[peerId] = fileId;

          // Initialize the memory buffer/transfer object
          _inboundTransfers[fileId] = InboundFileTransfer(
            fileId: fileId,
            fileName: fileName,
            fileSize: fileSize,
            chunkCount: chunkCount,
          );

          // Create the MessageModel in the database to show it in the chat UI
          final incomingMessage = MessageModel(
            id: fileId,
            peerId: peerId,
            senderId: senderId,
            messageType: 'FILE',
            content: fileName, // Start with fileName, will be updated to local path on completion
            timestamp: DateTime.now(),
            fileSizeInBytes: fileSize,
            bytesTransferred: 0,
            fileProgress: 0.0,
            isTransferComplete: false,
          );
          await _databaseService.addMessage(incomingMessage);
          print('[WebRTCService] Initialized inbound file transfer: $fileName ($fileSize bytes, $chunkCount chunks)');
          return;
        }

        final incomingMessage = MessageModel.fromJson(json).copyWith(
          peerId: peerId,
        );

        // Commit message to Hive local storage
        await _databaseService.addMessage(incomingMessage);
      }
    } catch (e) {
      print('[WebRTCService] Error handling incoming data channel message: $e');
    }
  }

  /// Sends a text message to a specific peer over the WebRTC Data Channel and commits it to Hive DB
  Future<void> sendMessage(String peerId, String content) async {
    final channel = _dataChannels[peerId];
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('P2P connection channel is not open for peer $peerId');
    }

    final message = MessageModel(
      id: const Uuid().v4(),
      peerId: peerId,
      senderId: _signalingService.localPeerId,
      messageType: 'TEXT',
      content: content,
      timestamp: DateTime.now(),
    );

    try {
      // Serialize and send the message via WebRTC
      final payload = jsonEncode(message.toJson());
      await channel.send(RTCDataChannelMessage(payload));

      // Save the message locally
      await _databaseService.addMessage(message);
    } catch (e) {
      print('[WebRTCService] Error sending P2P message to $peerId: $e');
      rethrow;
    }
  }

  /// Publishes state transitions to UI consumers
  void _updateConnectionState(String peerId, String state) {
    _connectionStates[peerId] = state;
    _connectionStateController.add(PeerConnectionStateUpdate(peerId, state));
    print('[WebRTCService] Connection state transition for $peerId -> $state');
  }

  /// Saves the fully assembled byte array of a received file transfer to storage.
  Future<void> _saveAssembledFile(InboundFileTransfer transfer) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savePath = '${directory.path}/${transfer.fileName}';
      final file = File(savePath);

      final builder = BytesBuilder();
      for (final chunk in transfer.chunks) {
        builder.add(chunk);
      }
      await file.writeAsBytes(builder.takeBytes());
      print('[WebRTCService] File saved successfully to: $savePath');

      final existingMsg = _databaseService.getMessageById(transfer.fileId);
      if (existingMsg != null) {
        final updatedMsg = existingMsg.copyWith(
          content: savePath,
          isTransferComplete: true,
          fileProgress: 1.0,
          bytesTransferred: transfer.fileSize,
        );
        await _databaseService.updateMessage(updatedMsg);
      }
    } catch (e) {
      print('[WebRTCService] Error saving assembled file: $e');
    }
  }

  /// Sends a file to a specific peer over the WebRTC Data Channel in 32KB binary chunks.
  Future<void> sendFileInChunks(String peerId, String filePath) async {
    final channel = _dataChannels[peerId];
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('P2P connection channel is not open for peer $peerId');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final fileName = file.path.split(Platform.pathSeparator).last;
    final fileSize = await file.length();
    final fileId = const Uuid().v4();

    const chunkSizeBytes = 32 * 1024; // 32KB
    final chunkCount = (fileSize / chunkSizeBytes).ceil();

    // 1. Metadata Step: send file transfer initialization packet
    final initPacket = {
      'type': 'FILE_INIT',
      'fileId': fileId,
      'fileName': fileName,
      'fileSize': fileSize,
      'chunkCount': chunkCount,
      'senderId': _signalingService.localPeerId,
    };

    await channel.send(RTCDataChannelMessage(jsonEncode(initPacket)));

    // Create and save local MessageModel for this file transfer
    final message = MessageModel(
      id: fileId,
      peerId: peerId,
      senderId: _signalingService.localPeerId,
      messageType: 'FILE',
      content: filePath, // Store the local path for the sender
      timestamp: DateTime.now(),
      fileSizeInBytes: fileSize,
      bytesTransferred: 0,
      fileProgress: 0.0,
      isTransferComplete: false,
    );
    await _databaseService.addMessage(message);

    // 2. Read file and send in chunks
    final raf = await file.open(mode: FileMode.read);
    int bytesSent = 0;

    try {
      while (bytesSent < fileSize) {
        final remaining = fileSize - bytesSent;
        final sizeToRead = remaining < chunkSizeBytes ? remaining : chunkSizeBytes;
        final chunk = await raf.read(sizeToRead);

        // Check backpressure before sending (threshold e.g. 1MB)
        while (channel.bufferedAmount != null && channel.bufferedAmount! > 1024 * 1024) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        await channel.send(RTCDataChannelMessage.fromBinary(chunk));
        bytesSent += chunk.length;

        // Update local database message progress
        final isComplete = bytesSent >= fileSize;
        final updatedMsg = message.copyWith(
          bytesTransferred: bytesSent,
          fileProgress: isComplete ? 1.0 : (bytesSent / fileSize),
          isTransferComplete: isComplete,
        );
        await _databaseService.updateMessage(updatedMsg);
      }
      print('[WebRTCService] File sent successfully: $fileName');
    } catch (e) {
      print('[WebRTCService] Error in sendFileInChunks loop: $e');
      rethrow;
    } finally {
      await raf.close();
    }
  }

  /// Clears resources when a peer disconnected
  void _cleanupPeerResources(String peerId) {
    _dataChannels[peerId]?.close();
    _dataChannels.remove(peerId);

    _peerConnections[peerId]?.close();
    _peerConnections.remove(peerId);

    print('[WebRTCService] Resources cleaned up for peer $peerId');
  }

  /// Safely disconnect and release all connections
  void dispose() {
    _signalingSubscription?.cancel();
    final activePeers = List<String>.from(_peerConnections.keys);
    for (final peerId in activePeers) {
      _cleanupPeerResources(peerId);
    }
    _connectionStateController.close();
    print('[WebRTCService] Service disposed');
  }
}

class InboundFileTransfer {
  final String fileId;
  final String fileName;
  final int fileSize;
  final int chunkCount;
  final List<Uint8List> chunks = [];
  int bytesTransferred = 0;

  InboundFileTransfer({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.chunkCount,
  });
}
