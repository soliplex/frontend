import 'status_message.dart';

sealed class MessageDisplay {
  const MessageDisplay();
}

final class MessageHidden extends MessageDisplay {
  const MessageHidden();
}

final class MessagePersistent extends MessageDisplay {
  const MessagePersistent();
}

final class MessageUpcoming extends MessageDisplay {
  const MessageUpcoming(this.remaining);
  final Duration remaining;
}

final class MessageActive extends MessageDisplay {
  const MessageActive(this.remaining);
  final Duration remaining;
}

MessageDisplay resolveVisibility(StatusMessage message,
    {required DateTime now}) {
  final window = message.window;
  // A windowless message — or a malformed window (end before start) — shows as
  // a plain persistent notice; a reversed window has no sensible countdown.
  if (window == null || !window.isValid) return const MessagePersistent();
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
