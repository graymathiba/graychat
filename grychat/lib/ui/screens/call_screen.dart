import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/network/call_service.dart';
import '../../core/providers/call_provider.dart';
import '../../core/providers/database_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String peerId;
  final String peerName;
  final CallType callType;

  const CallScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.callType,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  StreamSubscription<void>? _videoSub;
  StreamSubscription<CallInfo?>? _callSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callService = ref.read(callServiceProvider);

      // Direct stream subscription — more reliable than ref.listen for pop
      _callSub = callService.callInfoStream.listen((info) {
        if (!mounted) return;
        if (info == null ||
            info.state == CallState.idle ||
            info.state == CallState.ended) {
          Navigator.of(context).pop();
        }
      });

      _videoSub = callService.videoStateStream.listen((_) {
        if (mounted) setState(() {});
      });

      // Periodic refresh to ensure video views update when streams attach
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });

      final profile = ref.read(userProfileProvider);
      if (profile != null && profile.firstName.isNotEmpty) {
        callService.localDisplayName = profile.lastName.isNotEmpty
            ? '${profile.firstName} ${profile.lastName}'
            : profile.firstName;
      }

      callService.startCall(widget.peerId, widget.peerName, widget.callType);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _videoSub?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callInfoAsync = ref.watch(callInfoProvider);
    final callService = ref.read(callServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: callInfoAsync.when(
          data: (callInfo) {
            if (callInfo == null) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return _buildCallUI(callService, callInfo);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          error: (_, _) => const Center(
            child: Text('Call error', style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }

  Widget _buildCallUI(CallService callService, CallInfo callInfo) {
    final isVideo = callInfo.callType == CallType.video;
    final isActive = callInfo.state == CallState.active;
    final statusText = _statusText(callInfo);
    final durationText = _formatDuration(callInfo.duration);

    return Column(
      children: [
        // ── Remote Video (full screen) or Avatar ──
        Expanded(
          child: isVideo && isActive
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    RTCVideoView(
                      callService.remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                    // Local video pip
                    Positioned(
                      top: 16,
                      right: 16,
                      width: 120,
                      height: 160,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: Colors.black,
                          child: RTCVideoView(
                            callService.localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B4EBA),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.peerName.isNotEmpty
                              ? widget.peerName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF10B981)
                              : Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 4),
                        Text(
                          durationText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),

        // ── Controls ──
        if (isActive || callInfo.state == CallState.outgoingRinging)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (isVideo) ...[
                  _buildControlButton(
                    icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                    label: _isCameraOff ? 'Camera Off' : 'Camera On',
                    onTap: () async {
                      await callService.toggleCamera();
                      setState(() => _isCameraOff = !_isCameraOff);
                    },
                  ),
                  _buildControlButton(
                    icon: Icons.cameraswitch,
                    label: 'Flip',
                    onTap: () => callService.toggleCameraFacing(),
                  ),
                ],
                _buildControlButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  onTap: () async {
                    await callService.toggleMute();
                    setState(() => _isMuted = !_isMuted);
                  },
                ),
                _buildControlButton(
                  icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                  label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                  onTap: () {
                    setState(() => _isSpeakerOn = !_isSpeakerOn);
                  },
                ),
                _buildControlButton(
                  icon: Icons.call_end,
                  label: 'End',
                  color: const Color(0xFFEF4444),
                  onTap: () => callService.endCall(),
                ),
              ],
            ),
          ),

        // Incoming call: answer/reject
        if (callInfo.state == CallState.incomingRinging)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: const Color(0xFFEF4444),
                  onTap: () => callService.rejectCall(),
                ),
                _buildControlButton(
                  icon: Icons.call,
                  label: 'Accept',
                  color: const Color(0xFF10B981),
                  onTap: () => callService.answerCall(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = const Color(0xFF334155),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _statusText(CallInfo info) {
    switch (info.state) {
      case CallState.outgoingRinging:
        return 'Ringing...';
      case CallState.incomingRinging:
        return 'Incoming call...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.active:
        return info.callType == CallType.video ? 'Video Call' : 'Voice Call';
      case CallState.ended:
        return 'Call ended';
      case CallState.idle:
        return '';
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}
