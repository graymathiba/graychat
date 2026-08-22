import 'package:hive/hive.dart';
import '../models/group.dart';

class GroupAdapter extends TypeAdapter<Group> {
  @override
  final int typeId = 5;

  @override
  Group read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Group(
      id: fields[0] as String,
      name: fields[1] as String,
      creatorId: fields[2] as String,
      memberIds: (fields[3] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: fields[4] as DateTime,
      avatarBase64: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Group obj) {
    writer.writeByte(6);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.name);
    writer.writeByte(2);
    writer.write(obj.creatorId);
    writer.writeByte(3);
    writer.write(obj.memberIds);
    writer.writeByte(4);
    writer.write(obj.createdAt);
    writer.writeByte(5);
    writer.write(obj.avatarBase64);
  }
}
