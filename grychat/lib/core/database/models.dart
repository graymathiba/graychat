import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class PeerModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String deviceName;

  @HiveField(2)
  String localIP;

  @HiveField(3)
  String publicIP;

  @HiveField(4)
  String lastKnownPort;

  @HiveField(5)
  bool isOnline;

  @HiveField(6)
  DateTime lastSeen;

  @HiveField(7)
  String connectionType;

  @HiveField(8)
  String? phoneNumber;

  @HiveField(9)
  String? profilePicBase64;

  PeerModel({
    required this.id,
    required this.deviceName,
    required this.localIP,
    required this.publicIP,
    required this.lastKnownPort,
    required this.isOnline,
    required this.lastSeen,
    required this.connectionType,
    this.phoneNumber,
    this.profilePicBase64,
  });

  factory PeerModel.fromJson(Map<String, dynamic> json) {
    return PeerModel(
      id: json['id'] as String,
      deviceName: json['deviceName'] as String,
      localIP: json['localIP'] as String,
      publicIP: json['publicIP'] as String,
      lastKnownPort: json['lastKnownPort'] as String,
      isOnline: json['isOnline'] as bool,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      connectionType: json['connectionType'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      profilePicBase64: json['profilePicBase64'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'localIP': localIP,
      'publicIP': publicIP,
      'lastKnownPort': lastKnownPort,
      'isOnline': isOnline,
      'lastSeen': lastSeen.toIso8601String(),
      'connectionType': connectionType,
      'phoneNumber': phoneNumber,
      'profilePicBase64': profilePicBase64,
    };
  }

  PeerModel copyWith({
    String? id,
    String? deviceName,
    String? localIP,
    String? publicIP,
    String? lastKnownPort,
    bool? isOnline,
    DateTime? lastSeen,
    String? connectionType,
    String? phoneNumber,
    String? profilePicBase64,
  }) {
    return PeerModel(
      id: id ?? this.id,
      deviceName: deviceName ?? this.deviceName,
      localIP: localIP ?? this.localIP,
      publicIP: publicIP ?? this.publicIP,
      lastKnownPort: lastKnownPort ?? this.lastKnownPort,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      connectionType: connectionType ?? this.connectionType,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePicBase64: profilePicBase64 ?? this.profilePicBase64,
    );
  }

  @override
  String toString() => 'PeerModel(id: $id, deviceName: $deviceName, isOnline: $isOnline)';
}

@HiveType(typeId: 1)
class MessageModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String peerId;

  @HiveField(2)
  final String senderId;

  @HiveField(3)
  final String messageType;

  @HiveField(4)
  final String content;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  double fileProgress;

  @HiveField(7)
  bool isTransferComplete;

  @HiveField(8)
  int fileSizeInBytes;

  @HiveField(9)
  int bytesTransferred;

  MessageModel({
    required this.id,
    required this.peerId,
    required this.senderId,
    required this.messageType,
    required this.content,
    required this.timestamp,
    this.fileProgress = 0.0,
    this.isTransferComplete = false,
    this.fileSizeInBytes = 0,
    this.bytesTransferred = 0,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      peerId: json['peerId'] as String,
      senderId: json['senderId'] as String,
      messageType: json['messageType'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      fileProgress: (json['fileProgress'] as num?)?.toDouble() ?? 0.0,
      isTransferComplete: json['isTransferComplete'] as bool? ?? false,
      fileSizeInBytes: json['fileSizeInBytes'] as int? ?? 0,
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'peerId': peerId,
      'senderId': senderId,
      'messageType': messageType,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'fileProgress': fileProgress,
      'isTransferComplete': isTransferComplete,
      'fileSizeInBytes': fileSizeInBytes,
      'bytesTransferred': bytesTransferred,
    };
  }

  MessageModel copyWith({
    String? id,
    String? peerId,
    String? senderId,
    String? messageType,
    String? content,
    DateTime? timestamp,
    double? fileProgress,
    bool? isTransferComplete,
    int? fileSizeInBytes,
    int? bytesTransferred,
  }) {
    return MessageModel(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      senderId: senderId ?? this.senderId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      fileProgress: fileProgress ?? this.fileProgress,
      isTransferComplete: isTransferComplete ?? this.isTransferComplete,
      fileSizeInBytes: fileSizeInBytes ?? this.fileSizeInBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    );
  }

  double get calculatedProgress => fileSizeInBytes > 0 ? bytesTransferred / fileSizeInBytes : 0.0;

  @override
  String toString() => 'MessageModel(id: $id, peerId: $peerId, messageType: $messageType, progress: ${(calculatedProgress * 100).toStringAsFixed(2)}%)';
}

@HiveType(typeId: 2)
class UserProfile extends HiveObject {
  @HiveField(0)
  String firstName;

  @HiveField(1)
  String lastName;

  @HiveField(2)
  String phoneNumber;

  @HiveField(3)
  String? profilePicPath;

  @HiveField(4)
  String? profilePicBase64;

  @HiveField(5)
  String userId;

  @HiveField(6)
  String? username;

  UserProfile({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.profilePicPath,
    this.profilePicBase64,
    this.userId = '',
    this.username,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      profilePicPath: json['profilePicPath'] as String?,
      profilePicBase64: json['profilePicBase64'] as String?,
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'profilePicPath': profilePicPath,
      'profilePicBase64': profilePicBase64,
      'userId': userId,
      'username': username,
    };
  }

  UserProfile copyWith({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? profilePicPath,
    String? profilePicBase64,
    String? userId,
    String? username,
  }) {
    return UserProfile(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePicPath: profilePicPath ?? this.profilePicPath,
      profilePicBase64: profilePicBase64 ?? this.profilePicBase64,
      userId: userId ?? this.userId,
      username: username ?? this.username,
    );
  }

  @override
  String toString() => 'UserProfile($firstName $lastName, $phoneNumber)';
}
