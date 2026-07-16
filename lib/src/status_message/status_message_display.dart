import 'status_message.dart';

sealed class MessageDisplay {
  const MessageDisplay();
}

class MessageHidden extends MessageDisplay {
  const MessageHidden();
}

class MessagePersistent extends MessageDisplay {
  const MessagePersistent();
}

class MessageUpcoming extends MessageDisplay {
  const MessageUpcoming(this.remaining);
  final Duration remaining;
}

class MessageActive extends MessageDisplay {
  const MessageActive(this.remaining);
  final Duration remaining;
}

MessageDisplay resolveVisibility(StatusMessage message,
    {required DateTime now}) {
  final window = message.window;
  if (window == null) return const MessagePersistent();
  if (!now.isBefore(window.end)) return const MessageHidden();
  if (now.isBefore(window.start)) {
    return MessageUpcoming(window.start.difference(now));
  }
  return MessageActive(window.end.difference(now));
}

String formatCountdown(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final days = total.inDays;
  final hours = total.inHours % 24;
  final minutes = total.inMinutes % 60;
  if (days > 0) return '${days}D ${hours}H';
  if (hours > 0) return '${hours}H ${minutes}M';
  return '${minutes}M';
}
