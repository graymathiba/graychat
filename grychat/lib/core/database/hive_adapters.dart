import 'package:hive/hive.dart';
import 'models.dart';

class PeerModelAdapter extends TypeAdapter<PeerModel> {
  @override
  final int typeId = 0;

  @override
  PeerModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PeerModel(
      id: fields[0] as String,
      deviceName: fields[1] as String,
      localIP: fields[2] as String,
      publicIP: fields[3] as String,
      lastKnownPort: fields[4] as String,
      isOnline: fields[5] as bool,
      lastSeen: fields[6] as DateTime,
      connectionType: fields[7] as String,
      phoneNumber: fields[8] as String?,
      profilePicBase64: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PeerModel obj) {
    writer.writeByte(10);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.deviceName);
    writer.writeByte(2);
    writer.write(obj.localIP);
    writer.writeByte(3);
    writer.write(obj.publicIP);
    writer.writeByte(4);
    writer.write(obj.lastKnownPort);
    writer.writeByte(5);
    writer.write(obj.isOnline);
    writer.writeByte(6);
    writer.write(obj.lastSeen);
    writer.writeByte(7);
    writer.write(obj.connectionType);
    writer.writeByte(8);
    writer.write(obj.phoneNumber);
    writer.writeByte(9);
    writer.write(obj.profilePicBase64);
  }
}

class MessageModelAdapter extends TypeAdapter<MessageModel> {
  @override
  final int typeId = 1;

  @override
  MessageModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MessageModel(
      id: fields[0] as String,
      peerId: fields[1] as String,
      senderId: fields[2] as String,
      messageType: fields[3] as String,
      content: fields[4] as String,
      timestamp: fields[5] as DateTime,
      fileProgress: fields[6] as double? ?? 0.0,
      isTransferComplete: fields[7] as bool? ?? false,
      fileSizeInBytes: fields[8] as int? ?? 0,
      bytesTransferred: fields[9] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, MessageModel obj) {
    writer.writeByte(10);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.peerId);
    writer.writeByte(2);
    writer.write(obj.senderId);
    writer.writeByte(3);
    writer.write(obj.messageType);
    writer.writeByte(4);
    writer.write(obj.content);
    writer.writeByte(5);
    writer.write(obj.timestamp);
    writer.writeByte(6);
    writer.write(obj.fileProgress);
    writer.writeByte(7);
    writer.write(obj.isTransferComplete);
    writer.writeByte(8);
    writer.write(obj.fileSizeInBytes);
    writer.writeByte(9);
    writer.write(obj.bytesTransferred);
  }
}

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 2;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      firstName: fields[0] as String,
      lastName: fields[1] as String,
      phoneNumber: fields[2] as String,
      profilePicPath: fields[3] as String?,
      profilePicBase64: fields[4] as String?,
      userId: fields[5] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer.writeByte(6);
    writer.writeByte(0);
    writer.write(obj.firstName);
    writer.writeByte(1);
    writer.write(obj.lastName);
    writer.writeByte(2);
    writer.write(obj.phoneNumber);
    writer.writeByte(3);
    writer.write(obj.profilePicPath);
    writer.writeByte(4);
    writer.write(obj.profilePicBase64);
    writer.writeByte(5);
    writer.write(obj.userId);
  }
}
