import 'package:dart_monty/dart_monty_bridge.dart'
    show BridgeMiddleware, CallRole, InfraCall, ToolCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart'
    show AllowOnce, AllowSession, Deny;

import 'package:soliplex_frontend/src/modules/room/access_policy.dart';
import 'package:soliplex_frontend/src/modules/room/policy_enforcement_middleware.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<Object?> _callTool(
  BridgeMiddleware mw,
  String name, {
  Map<String, Object?> args = const {},
  CallRole role = const ToolCall(),
}) {
  Future<Object?> next(String n, Map<String, Object?> a) async => 'result:$n';
  return mw.handle(name, args, role, next);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PolicyEnforcementMiddleware', () {
    group('InfraCall bypass', () {
      test('always passes through infra calls regardless of policy', () async {
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            toolFilter: ToolFilter(allowedTools: {}), // block everything
          ),
        );
        final result = await _callTool(
          mw,
          '__restore_state__',
          role: const InfraCall(),
        );
        expect(result, 'result:__restore_state__');
      });
    });

    group('tool filter', () {
      test('permissive policy allows all tools', () async {
        final mw = PolicyEnforcementMiddleware(AccessPolicy.permissive);
        final result = await _callTool(mw, 'soliplex_list_rooms');
        expect(result, 'result:soliplex_list_rooms');
      });

      test('throws StateError when tool not in allowlist', () async {
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            toolFilter: ToolFilter(allowedTools: {'tool_a'}),
          ),
        );
        await expectLater(
          () => _callTool(mw, 'tool_b'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('tool_b'),
            ),
          ),
        );
      });

      test('allows tool in allowlist', () async {
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            toolFilter: ToolFilter(allowedTools: {'tool_a'}),
          ),
        );
        final result = await _callTool(mw, 'tool_a');
        expect(result, 'result:tool_a');
      });

      test('blocks explicitly denied tool', () async {
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            toolFilter: ToolFilter(deniedTools: {'bad_tool'}),
          ),
        );
        await expectLater(
          () => _callTool(mw, 'bad_tool'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('HITL — AllowOnce', () {
      test('calls onHitl and proceeds without adding to session approved',
          () async {
        var hitlCalled = false;
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            hitlPolicy: HitlPolicy(requireApprovalForTools: {'get_clipboard'}),
          ),
          onHitl: (name, args) async {
            hitlCalled = true;
            return const AllowOnce();
          },
        );

        final result = await _callTool(mw, 'get_clipboard');
        expect(hitlCalled, isTrue);
        expect(result, 'result:get_clipboard');

        // Second call should prompt again (AllowOnce — not persisted)
        hitlCalled = false;
        await _callTool(mw, 'get_clipboard');
        expect(hitlCalled, isTrue);
      });
    });

    group('HITL — AllowSession', () {
      test('first call invokes onHitl; subsequent calls skip it', () async {
        var hitlCount = 0;
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            hitlPolicy: HitlPolicy(requireApprovalForTools: {'get_clipboard'}),
          ),
          onHitl: (name, args) async {
            hitlCount++;
            return const AllowSession();
          },
        );

        await _callTool(mw, 'get_clipboard');
        expect(hitlCount, 1);

        await _callTool(mw, 'get_clipboard');
        expect(hitlCount, 1); // no second prompt
      });
    });

    group('HITL — Deny', () {
      test('throws StateError and calls onDeny', () async {
        var denyFired = false;
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            hitlPolicy: HitlPolicy(requireApprovalForTools: {'get_clipboard'}),
          ),
          onHitl: (_, __) async => const Deny(),
          onDeny: () => denyFired = true,
        );

        await expectLater(
          () => _callTool(mw, 'get_clipboard'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('get_clipboard'),
            ),
          ),
        );
        expect(denyFired, isTrue);
      });
    });

    group('no HITL callback', () {
      test('skips HITL check when onHitl is null', () async {
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            hitlPolicy: HitlPolicy(requireApprovalForTools: {'get_clipboard'}),
          ),
          // No onHitl — tool should pass through
        );
        final result = await _callTool(mw, 'get_clipboard');
        expect(result, 'result:get_clipboard');
      });
    });

    group('policy setter', () {
      test('updating policy takes effect immediately', () async {
        final mw = PolicyEnforcementMiddleware(AccessPolicy.permissive);

        // Initially allowed
        final r1 = await _callTool(mw, 'tool_a');
        expect(r1, 'result:tool_a');

        // Tighten policy
        mw.policy = const AccessPolicy(
          toolFilter: ToolFilter(allowedTools: {'tool_b'}),
        );

        await expectLater(
          () => _callTool(mw, 'tool_a'),
          throwsA(isA<StateError>()),
        );
        final r2 = await _callTool(mw, 'tool_b');
        expect(r2, 'result:tool_b');
      });
    });

    group('HITL by namespace', () {
      test('requireApprovalForNamespaces triggers HITL for all tools in ns',
          () async {
        var hitlCalled = false;
        final mw = PolicyEnforcementMiddleware(
          const AccessPolicy(
            hitlPolicy: HitlPolicy(
              requireApprovalForNamespaces: {'soliplex'},
            ),
          ),
          onHitl: (name, args) async {
            hitlCalled = true;
            return const AllowOnce();
          },
        );

        await _callTool(mw, 'soliplex_list_rooms');
        expect(hitlCalled, isTrue);

        hitlCalled = false;
        await _callTool(mw, 'soliplex_send_message');
        expect(hitlCalled, isTrue);

        hitlCalled = false;
        await _callTool(mw, 'notify_show');
        expect(hitlCalled, isFalse); // different namespace — no HITL
      });
    });
  });
}
