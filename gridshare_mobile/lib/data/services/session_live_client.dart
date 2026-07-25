import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart' show kProductionBaseUrl;

/// A single live event pushed from the backend WebSocket hub (`/ws`).
/// Mirrors the eventBus envelope: `{ id, type, payload, timestamp }`.
class LiveEvent {
  final String type;
  final Map<String, dynamic> payload;

  const LiveEvent({required this.type, required this.payload});

  factory LiveEvent.fromJson(Map<String, dynamic> j) => LiveEvent(
        type: j['type'] as String? ?? 'unknown',
        payload: (j['payload'] as Map<String, dynamic>?) ?? const {},
      );

  // Convenience getters for the meter-tick / settlement payloads.
  int? get billedMinutes => (payload['billedMinutes'] as num?)?.toInt();
  int? get amountDueCredits => (payload['amountDueCredits'] as num?)?.toInt();
  int? get remainingCredits => (payload['remainingCredits'] as num?)?.toInt();
  int? get activeSeconds => (payload['activeSeconds'] as num?)?.toInt();
  String? get reason => payload['reason'] as String?;
}

/// Streams live session events from the backend WebSocket hub.
///
/// The hub broadcasts telemetry, meter ticks, activation, auto-stop and
/// settlement. Scope the stream to one session with [sessionId] or one host
/// with [hostId]. Falls back gracefully: if the socket drops it emits nothing
/// further (callers should keep their last-known state), and [reconnect] can be
/// used to re-establish. Derives the ws:// URL from the same base host the
/// [ApiService] talks to so dev/prod stay in sync.
class SessionLiveClient {
  SessionLiveClient({
    String? baseUrl,
    this.sessionId,
    this.hostId,
  }) : _baseUrl = baseUrl ?? _defaultBaseUrl;

  final String _baseUrl;
  final String? sessionId;
  final String? hostId;

  WebSocketChannel? _channel;
  StreamController<LiveEvent>? _controller;

  static String get _defaultBaseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    return envUrl.isNotEmpty ? envUrl : kProductionBaseUrl;
  }

  /// Build the ws(s):// URL for the hub, carrying the scope filter.
  Uri get _wsUri {
    final http = Uri.parse(_baseUrl);
    final scheme = http.scheme == 'https' ? 'wss' : 'ws';
    final query = <String, String>{
      if (sessionId != null) 'sessionId': sessionId!,
      if (hostId != null) 'hostId': hostId!,
    };
    return Uri(
      scheme: scheme,
      host: http.host,
      port: http.hasPort ? http.port : null,
      path: '/ws',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  /// Open the socket and return a broadcast stream of [LiveEvent]s.
  /// The `ws.connected` greeting is filtered out; callers only see real events.
  Stream<LiveEvent> connect() {
    _controller = StreamController<LiveEvent>.broadcast(
      onCancel: dispose,
    );
    _open();
    return _controller!.stream;
  }

  void _open() {
    try {
      _channel = WebSocketChannel.connect(_wsUri);
      _channel!.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
            final event = LiveEvent.fromJson(decoded);
            if (event.type == 'ws.connected') return; // skip greeting
            _controller?.add(event);
          } catch (_) {
            // Ignore malformed frames — keep the stream alive.
          }
        },
        onError: (Object e) => _controller?.addError(e),
        onDone: () => _controller?.close(),
        cancelOnError: false,
      );
    } catch (e) {
      _controller?.addError(e);
    }
  }

  /// Tear down the socket. Safe to call multiple times.
  void dispose() {
    _channel?.sink.close();
    _channel = null;
    if (!(_controller?.isClosed ?? true)) _controller?.close();
    _controller = null;
  }
}
