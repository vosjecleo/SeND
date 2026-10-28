enum HistoryRoomKind { dm, group, server }

enum HistoryScope {
  dms('DMs'),
  groups('DMs and group chats'),
  all('DMs, group chats and server history');

  const HistoryScope(this.label);
  final String label;

  bool includes(HistoryRoomKind kind) => switch (this) {
    dms => kind == HistoryRoomKind.dm,
    groups => kind != HistoryRoomKind.server,
    all => true,
  };

  static HistoryScope parse(Object? value) =>
      values.where((scope) => scope.name == value).firstOrNull ?? all;
}
