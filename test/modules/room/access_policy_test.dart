import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/access_policy.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ToolFilter
  // ---------------------------------------------------------------------------
  group('ToolFilter', () {
    test('permissive allows any tool', () {
      const f = ToolFilter.permissive;
      expect(f.allows('soliplex_list_rooms'), isTrue);
      expect(f.allows('notify_show'), isTrue);
      expect(f.allows('get_clipboard'), isTrue);
    });

    test('deniedTools blocks named tool even if allowlist is null', () {
      const f = ToolFilter(deniedTools: {'bad_tool'});
      expect(f.allows('bad_tool'), isFalse);
      expect(f.allows('good_tool'), isTrue);
    });

    test('allowedTools allowlist blocks tools not in it', () {
      const f =
          ToolFilter(allowedTools: {'soliplex_list_rooms', 'notify_show'});
      expect(f.allows('soliplex_list_rooms'), isTrue);
      expect(f.allows('notify_show'), isTrue);
      expect(f.allows('get_clipboard'), isFalse);
    });

    test('allowedNamespaces blocks tools from other namespaces', () {
      const f = ToolFilter(allowedNamespaces: {'soliplex', 'notify'});
      expect(f.allows('soliplex_list_rooms'), isTrue);
      expect(f.allows('notify_show'), isTrue);
      expect(f.allows('get_clipboard'), isFalse);
    });

    test('deniedTools applied after allowlist', () {
      const f = ToolFilter(
        allowedTools: {'tool_a', 'tool_b'},
        deniedTools: {'tool_a'},
      );
      expect(f.allows('tool_a'), isFalse);
      expect(f.allows('tool_b'), isTrue);
    });

    test('tool with no underscore uses full name as namespace', () {
      const f = ToolFilter(allowedNamespaces: {'clipboard'});
      expect(f.allows('clipboard'), isTrue);
      expect(f.allows('other'), isFalse);
    });

    test('fromAllowlist(null) returns permissive', () {
      final f = ToolFilter.fromAllowlist(null);
      expect(f.allows('anything'), isTrue);
    });

    test('fromAllowlist([...]) restricts to listed tools', () {
      final f = ToolFilter.fromAllowlist(['tool_a', 'tool_b']);
      expect(f.allows('tool_a'), isTrue);
      expect(f.allows('tool_c'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // OsFilter
  // ---------------------------------------------------------------------------
  group('OsFilter', () {
    test('permissive allows all ops', () {
      const f = OsFilter.permissive;
      expect(f.allows('Path.read_text'), isTrue);
      expect(f.allows('Path.write_text'), isTrue);
      expect(f.allows('os.getenv'), isTrue);
    });

    test('readOnly denies write ops', () {
      const f = OsFilter.readOnly;
      expect(f.allows('Path.write_text'), isFalse);
      expect(f.allows('Path.write_bytes'), isFalse);
      expect(f.allows('Path.mkdir'), isFalse);
      expect(f.allows('Path.unlink'), isFalse);
      expect(f.allows('Path.rmdir'), isFalse);
      expect(f.allows('Path.rename'), isFalse);
    });

    test('readOnly allows read ops', () {
      const f = OsFilter.readOnly;
      expect(f.allows('Path.read_text'), isTrue);
      expect(f.allows('Path.exists'), isTrue);
      expect(f.allows('os.getenv'), isTrue);
    });

    test('allowedOps restricts to listed ops', () {
      const f = OsFilter(allowedOps: {'Path.read_text', 'os.getenv'});
      expect(f.allows('Path.read_text'), isTrue);
      expect(f.allows('os.getenv'), isTrue);
      expect(f.allows('Path.write_text'), isFalse);
    });

    test('deniedOps applied after allowedOps', () {
      const f = OsFilter(
        allowedOps: {'Path.read_text', 'Path.write_text'},
        deniedOps: {'Path.write_text'},
      );
      expect(f.allows('Path.read_text'), isTrue);
      expect(f.allows('Path.write_text'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // HitlPolicy
  // ---------------------------------------------------------------------------
  group('HitlPolicy', () {
    test('none requires no approvals', () {
      const p = HitlPolicy.none;
      expect(p.requires('get_clipboard'), isFalse);
      expect(p.requires('soliplex_list_rooms'), isFalse);
    });

    test('requireApprovalForTools matches exact tool name', () {
      const p = HitlPolicy(requireApprovalForTools: {'get_clipboard'});
      expect(p.requires('get_clipboard'), isTrue);
      expect(p.requires('get_device_info'), isFalse);
    });

    test('requireApprovalForNamespaces matches namespace prefix', () {
      const p = HitlPolicy(requireApprovalForNamespaces: {'soliplex'});
      expect(p.requires('soliplex_list_rooms'), isTrue);
      expect(p.requires('soliplex_send_message'), isTrue);
      expect(p.requires('notify_show'), isFalse);
    });

    test('combined: tool name takes precedence over namespace', () {
      const p = HitlPolicy(
        requireApprovalForTools: {'get_clipboard'},
        requireApprovalForNamespaces: {'notify'},
      );
      expect(p.requires('get_clipboard'), isTrue);
      expect(p.requires('notify_show'), isTrue);
      expect(p.requires('soliplex_list_rooms'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // AccessPolicy
  // ---------------------------------------------------------------------------
  group('AccessPolicy', () {
    test('permissive allows all hosts', () {
      const p = AccessPolicy.permissive;
      expect(p.hostAllowed('api.example.com'), isTrue);
      expect(p.hostAllowed('evil.com'), isTrue);
    });

    test('denyHosts blocks named host', () {
      const p = AccessPolicy(denyHosts: {'evil.com'});
      expect(p.hostAllowed('evil.com'), isFalse);
      expect(p.hostAllowed('safe.com'), isTrue);
    });

    test('allowHosts restricts to listed hosts', () {
      const p = AccessPolicy(allowHosts: {'api.soliplex.ai'});
      expect(p.hostAllowed('api.soliplex.ai'), isTrue);
      expect(p.hostAllowed('other.com'), isFalse);
    });

    test('denyHosts applied after allowHosts', () {
      const p = AccessPolicy(
        allowHosts: {'api.soliplex.ai', 'evil.com'},
        denyHosts: {'evil.com'},
      );
      expect(p.hostAllowed('api.soliplex.ai'), isTrue);
      expect(p.hostAllowed('evil.com'), isFalse);
    });

    group('fromRoomConfig', () {
      test('null lists produce permissive policy', () {
        final p = AccessPolicy.fromRoomConfig();
        expect(p.toolFilter.allows('anything'), isTrue);
        expect(p.osFilter.allows('Path.write_text'), isTrue);
        expect(p.hostAllowed('anywhere.com'), isTrue);
      });

      test('allowedTools restricts tool filter', () {
        final p = AccessPolicy.fromRoomConfig(
          allowedTools: ['tool_a'],
        );
        expect(p.toolFilter.allows('tool_a'), isTrue);
        expect(p.toolFilter.allows('tool_b'), isFalse);
      });

      test('deniedOsOps restricts os filter', () {
        final p = AccessPolicy.fromRoomConfig(
          deniedOsOps: ['Path.write_text'],
        );
        expect(p.osFilter.allows('Path.read_text'), isTrue);
        expect(p.osFilter.allows('Path.write_text'), isFalse);
      });

      test('requireApprovalForTools and namespaces populate hitl policy', () {
        final p = AccessPolicy.fromRoomConfig(
          requireApprovalForTools: ['get_clipboard'],
          requireApprovalForNamespaces: ['soliplex'],
        );
        expect(p.hitlPolicy.requires('get_clipboard'), isTrue);
        expect(p.hitlPolicy.requires('soliplex_list_rooms'), isTrue);
        expect(p.hitlPolicy.requires('notify_show'), isFalse);
      });
    });

    group('withSessionAllowances', () {
      test('empty set returns same policy', () {
        const p = AccessPolicy.permissive;
        final p2 = p.withSessionAllowances({});
        expect(identical(p, p2), isTrue);
      });

      test('adds tools to existing allowlist', () {
        const p = AccessPolicy(
          toolFilter: ToolFilter(allowedTools: {'tool_a'}),
        );
        final p2 = p.withSessionAllowances({'tool_b'});
        expect(p2.toolFilter.allows('tool_a'), isTrue);
        expect(p2.toolFilter.allows('tool_b'), isTrue);
        expect(p2.toolFilter.allows('tool_c'), isFalse);
      });

      test('when allowlist is null, session grants do not restrict', () {
        const p = AccessPolicy.permissive; // null = all allowed
        final p2 = p.withSessionAllowances({'tool_a'});
        expect(p2.toolFilter.allows('tool_a'), isTrue);
        expect(p2.toolFilter.allows('anything_else'), isTrue);
      });

      test('preserves osFilter and hitlPolicy', () {
        const p = AccessPolicy(
          toolFilter: ToolFilter(allowedTools: {'tool_a'}),
          osFilter: OsFilter.readOnly,
          hitlPolicy: HitlPolicy(requireApprovalForTools: {'get_clipboard'}),
        );
        final p2 = p.withSessionAllowances({'tool_b'});
        expect(p2.osFilter.allows('Path.write_text'), isFalse);
        expect(p2.hitlPolicy.requires('get_clipboard'), isTrue);
      });
    });
  });
}
