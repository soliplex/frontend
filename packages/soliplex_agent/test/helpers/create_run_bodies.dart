import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, HttpTransport, SoliplexApi, UrlBuilder;

class _MockHttpTransport extends Mock implements HttpTransport {}

/// An [AgUiLlmProvider] over the real [SoliplexApi] and a fake transport, so
/// what a test checks is the body of each run-creating POST the backend
/// receives, in order. The backend answers the runs `run-1`, `run-2`, … in
/// the order they are created.
///
/// The test registers a fallback `Uri` and `CancelToken` for mocktail.
({AgUiLlmProvider provider, List<Object?> createRunBodies})
    providerRecordingCreateRunBodies(AgUiStreamClient streamClient) {
  final transport = _MockHttpTransport();
  final createRunBodies = <Object?>[];
  when(
    () => transport.request<Map<String, dynamic>>(
      'POST',
      any(),
      body: any(named: 'body'),
      headers: any(named: 'headers'),
      timeout: any(named: 'timeout'),
      cancelToken: any(named: 'cancelToken'),
      fromJson: any(named: 'fromJson'),
    ),
  ).thenAnswer((invocation) async {
    createRunBodies.add(invocation.namedArguments[#body]);
    return {'run_id': 'run-${createRunBodies.length}'};
  });
  return (
    provider: AgUiLlmProvider(
      api: SoliplexApi(
        transport: transport,
        urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
      ),
      agUiStreamClient: streamClient,
    ),
    createRunBodies: createRunBodies,
  );
}
