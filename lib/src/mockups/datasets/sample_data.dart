import 'dart:math' as math;

import 'package:soliplex_client/soliplex_client.dart';

import '../chat/static_backend.dart';
import 'model.dart';
import 'store.dart';

/// The people and groups datasets can be shared with.
const _principals = [
  Principal(
    id: 'jdoe',
    name: 'J. Doe',
    kind: PrincipalKind.person,
    clearance: 'confidential',
    email: 'jdoe@example.com',
    detail: 'Plant maintenance',
  ),
  Principal(
    id: 'asmith',
    name: 'A. Smith',
    kind: PrincipalKind.person,
    clearance: 'confidential',
    email: 'asmith@example.com',
    detail: 'Ops/Logistics',
  ),
  Principal(
    id: 'bnguyen',
    name: 'B. Nguyen',
    kind: PrincipalKind.person,
    clearance: 'restricted',
    email: 'bnguyen@example.com',
    detail: 'Plant operations',
  ),
  Principal(
    id: 'cgarcia',
    name: 'C. Garcia',
    kind: PrincipalKind.person,
    clearance: 'internal',
    email: 'cgarcia@example.com',
    detail: 'Eng/Reliability',
  ),
  Principal(
    id: 'dlee',
    name: 'D. Lee',
    kind: PrincipalKind.person,
    clearance: 'public',
    email: 'dlee@contractor.example',
    detail: 'Contractor',
  ),
  Principal(
    id: 'erivera',
    name: 'E. Rivera',
    kind: PrincipalKind.person,
    clearance: 'confidential',
    email: 'erivera@example.com',
    detail: 'Shift team',
  ),
  Principal(
    id: 'g-ops-logistics',
    name: 'Ops/Logistics',
    kind: PrincipalKind.group,
    detail: 'Logistics and planning · 48 members',
  ),
  Principal(
    id: 'g-plant-mx',
    name: 'Plant/Maintenance',
    kind: PrincipalKind.group,
    detail: 'Plant maintenance team · 120 members',
  ),
  Principal(
    id: 'g-plant-shift',
    name: 'Plant/Shift team',
    kind: PrincipalKind.group,
    detail: 'Operators on shift · 61 members',
  ),
  Principal(
    id: 'g-eng-reliability',
    name: 'Eng/Reliability',
    kind: PrincipalKind.group,
    detail: 'Reliability engineering · 35 members',
  ),
];

const _user = MockUser(
  person: Principal(
    id: 'jdoe',
    name: 'J. Doe',
    kind: PrincipalKind.person,
    clearance: 'confidential',
    email: 'jdoe@example.com',
  ),
  groupIds: {'g-ops-logistics', 'g-plant-mx', 'g-plant-shift'},
);

const presets = [
  RoomPreset(
    roomId: 'plant-mx',
    name: 'Plant Maintenance',
    description: 'Troubleshooting and procedures for plant maintainers.',
    ceiling: 'internal',
    defaultDatasetIds: [
      'ops/pump-service-manuals',
      'eng/reliability-reports',
      'plant/relief-valve-systems',
    ],
    skills: ['RAG search', 'Data analysis', 'Python sandbox'],
  ),
  RoomPreset(
    roomId: 'ops-planning',
    name: 'Operations Planning',
    description: 'Shift scheduling and outage planning for the plant.',
    ceiling: 'confidential',
    defaultDatasetIds: [
      'plant/shift-planning-playbook',
      'plant/outage-planning-library',
    ],
    skills: ['RAG search', 'Scheduling'],
  ),
  RoomPreset(
    roomId: 'public-research',
    name: 'Public Research',
    description: 'Published standards, bulletins and open sources.',
    ceiling: 'public',
    defaultDatasetIds: [
      'ops/maintenance-policy-handbook',
      'ops/public-safety-bulletins',
    ],
    skills: ['RAG search', 'Web search'],
  ),
];

DateTime _ago(int days) => DateTime.now().subtract(Duration(days: days));

/// [count] files named after [stem], with [rawOnly] of them CSVs, all
/// searchable unless [done] says fewer ingestible ones are.
List<DatasetFile> _files(
  String stem,
  String level, {
  required int count,
  int rawOnly = 0,
  int? done,
  int addedDaysAgo = 30,
}) {
  final random = math.Random(stem.hashCode);
  final ingestible = count - rawOnly;
  final searchable = done ?? ingestible;
  return [
    for (var i = 0; i < count; i++)
      DatasetFile(
        name: i < ingestible
            ? '$stem-${(i + 1).toString().padLeft(3, '0')}'
                '.${const ['pdf', 'pdf', 'docx', 'pptx'][i % 4]}'
            : '$stem-data-${i - ingestible + 1}.csv',
        sizeBytes: 40000 + random.nextInt(6000000),
        level: level,
        addedAt: _ago(addedDaysAgo - i % addedDaysAgo.clamp(1, 30)),
        status: i >= ingestible
            ? FileStatus.sandboxOnly
            : i < searchable
                ? FileStatus.searchable
                : i == searchable
                    ? FileStatus.ingesting
                    : FileStatus.queued,
        // Fixed, not animated: seeded ingestion is a still picture.
        progress: i == searchable ? 0.4 : 0,
      ),
  ];
}

List<Dataset> _handcrafted() => [
      Dataset(
        namespace: 'ops',
        slug: 'pump-service-manuals',
        title: 'Pump service manuals',
        description: 'Current service manuals for the P-100 and P-200 pump '
            'lines, with the fault-isolation trees.',
        level: 'internal',
        ownerId: 'asmith',
        createdAt: _ago(400),
        updatedAt: _ago(3),
        files: _files('pump-manual', 'internal', count: 42)
          ..[5].outdated = OutdatedMark(
            reason: 'Superseded by revision 47: the coupling torque values '
                'changed.',
            by: 'asmith',
            at: _ago(3),
            replacedBy: 'pump-manual-001.pdf',
          ),
        audience: {'g-plant-mx', 'g-ops-logistics', 'g-eng-reliability'},
        tags: DatasetTags(
          keywords: {'pumps', 'service manuals', 'fault isolation'},
          systems: {'P-100', 'P-200'},
          affiliations: {'Ops › Plant › Maintenance'},
        ),
        uses: 310,
      ),
      Dataset(
        namespace: 'ops',
        slug: 'maintenance-trend-data',
        title: 'Maintenance trend data',
        description: 'Monthly work-order extracts and the analyses built on '
            'them. The extracts are CSVs: the agent reads them in its sandbox.',
        level: 'internal',
        ownerId: 'asmith',
        createdAt: _ago(200),
        updatedAt: _ago(9),
        files: _files('work-orders', 'internal', count: 22, rawOnly: 18),
        audience: {'g-ops-logistics', 'g-plant-mx'},
        tags: DatasetTags(
          keywords: {'maintenance data', 'trends', 'work orders'},
          systems: {'P-100'},
          affiliations: {'Ops › Logistics'},
        ),
        uses: 88,
      ),
      Dataset(
        namespace: 'plant',
        slug: 'shift-planning-playbook',
        title: 'Shift planning playbook',
        description: 'Peak-demand and steady-state staffing plans for the '
            'plant.',
        level: 'confidential',
        ownerId: 'bnguyen',
        createdAt: _ago(120),
        updatedAt: _ago(14),
        files: _files('shift-plan', 'confidential', count: 16),
        audience: {'g-plant-shift', 'g-plant-mx'},
        tags: DatasetTags(
          keywords: {'shift planning', 'peak demand'},
          systems: {'P-100'},
          affiliations: {'Ops › Plant'},
        ),
        uses: 140,
      ),
      Dataset(
        namespace: 'plant',
        slug: 'lockout-tagout-checklists',
        title: 'Lockout/tagout checklists',
        description: 'Lockout/tagout checklists and the safety standards they '
            'follow.',
        level: 'internal',
        ownerId: 'erivera',
        createdAt: _ago(6),
        updatedAt: _ago(1),
        files: _files('loto', 'internal', count: 40, done: 12),
        audience: {'g-plant-shift', 'g-plant-mx'},
        tags: DatasetTags(
          keywords: {'lockout/tagout', 'checklists'},
          systems: {'P-100'},
          affiliations: {'Ops › Plant › Maintenance › Shift team'},
        ),
        uses: 22,
      ),
      Dataset(
        namespace: 'eng',
        slug: 'reliability-reports',
        title: 'Reliability reports',
        description: 'Quarterly fleet reliability and overhaul reports.',
        level: 'internal',
        ownerId: 'cgarcia',
        createdAt: _ago(300),
        updatedAt: _ago(20),
        files: _files('reliability', 'internal', count: 28),
        audience: {'g-ops-logistics', 'g-plant-mx', 'g-eng-reliability'},
        tags: DatasetTags(
          keywords: {'reliability', 'overhaul'},
          systems: {'P-100', 'P-200'},
          affiliations: {'Eng › Reliability'},
        ),
        uses: 190,
      ),
      Dataset(
        namespace: 'eng',
        slug: 'legacy-pump-manuals-2019',
        title: 'Pump service manuals (2019 baseline)',
        description: 'The 2019 baseline of the pump service manuals.',
        level: 'internal',
        ownerId: 'cgarcia',
        createdAt: _ago(1500),
        updatedAt: _ago(60),
        files: _files('manual-2019', 'internal', count: 35),
        audience: {'g-ops-logistics', 'g-plant-mx'},
        tags: DatasetTags(
          keywords: {'pumps', 'service manuals'},
          systems: {'P-100'},
          affiliations: {'Eng › Reliability'},
        ),
        deprecation: Deprecation(
          reason: 'Superseded by the current manual revision; several fault '
              'trees changed.',
          by: 'cgarcia',
          at: _ago(60),
          replacedById: 'ops/pump-service-manuals',
        ),
        uses: 260,
      ),
      Dataset(
        namespace: 'ops',
        slug: 'maintenance-policy-handbook',
        title: 'Maintenance policy handbook',
        description: 'The published maintenance policy and its site '
            'supplements.',
        level: 'public',
        ownerId: 'asmith',
        createdAt: _ago(700),
        updatedAt: _ago(45),
        files: _files('policy', 'public', count: 6),
        audience: {
          'g-ops-logistics',
          'g-plant-mx',
          'g-plant-shift',
          'g-eng-reliability',
        },
        tags: DatasetTags(
          keywords: {'maintenance management', 'policy'},
          affiliations: {'Ops › Logistics'},
        ),
        uses: 420,
      ),
      Dataset(
        namespace: 'ops',
        slug: 'public-safety-bulletins',
        title: 'Public safety bulletins',
        description: 'Released workplace safety bulletins.',
        level: 'public',
        ownerId: 'asmith',
        createdAt: _ago(500),
        updatedAt: _ago(5),
        files: _files('safety-bulletin', 'public', count: 64),
        audience: {'g-ops-logistics', 'g-plant-mx', 'g-plant-shift'},
        tags: DatasetTags(
          keywords: {'safety', 'bulletins'},
          affiliations: {'Ops › Safety'},
        ),
        uses: 75,
      ),
      Dataset(
        namespace: 'plant',
        slug: 'outage-planning-library',
        title: 'Outage planning library',
        description: 'Planning templates and the outage team’s reference '
            'material.',
        level: 'confidential',
        ownerId: 'bnguyen',
        createdAt: _ago(10),
        updatedAt: _ago(2),
        files: _files('outage', 'confidential', count: 30, done: 9),
        audience: {'g-plant-shift'},
        tags: DatasetTags(
          keywords: {'outage planning'},
          affiliations: {'Ops › Plant › Operations'},
        ),
        uses: 31,
      ),
      Dataset(
        namespace: 'plant',
        slug: 'relief-valve-systems',
        title: 'Relief valve systems',
        description: 'Pressure relief valve maintenance references.',
        level: 'internal',
        ownerId: 'erivera',
        createdAt: _ago(260),
        updatedAt: _ago(30),
        files: _files('relief-valve', 'internal', count: 19),
        audience: {'g-plant-mx', 'g-plant-shift'},
        tags: DatasetTags(
          keywords: {'relief valves', 'pressure safety'},
          systems: {'P-100', 'P-200'},
          affiliations: {'Ops › Plant › Maintenance'},
        ),
        uses: 64,
      ),
      Dataset(
        namespace: 'eng',
        slug: 'bearing-failure-analysis',
        title: 'Bearing failure analysis',
        description: 'Engineering analyses of pump bearing and seal failures.',
        level: 'internal',
        ownerId: 'cgarcia',
        createdAt: _ago(150),
        updatedAt: _ago(25),
        files: _files('bearing-analysis', 'internal', count: 12, rawOnly: 3),
        audience: {'g-ops-logistics', 'g-eng-reliability'},
        tags: DatasetTags(
          keywords: {'bearings', 'failure analysis', 'pumps'},
          systems: {'P-100'},
          affiliations: {'Eng › Reliability'},
        ),
        uses: 40,
      ),
      Dataset(
        namespace: 'jdoe',
        slug: 'pump-quickref',
        title: 'My pump quick reference',
        description: 'Notes and excerpts I keep handy on the plant floor.',
        level: 'internal',
        ownerId: 'jdoe',
        createdAt: _ago(90),
        updatedAt: _ago(12),
        files: _files('quickref', 'internal', count: 7),
        audience: {'g-plant-mx'},
        tags: DatasetTags(
          keywords: {'pumps', 'quick reference'},
          systems: {'P-100'},
        ),
        uses: 18,
      ),
      Dataset(
        namespace: 'jdoe',
        slug: 'inspection-notes',
        title: 'Vibration inspection notes',
        description: 'Private notes from vibration inspections.',
        level: 'internal',
        ownerId: 'jdoe',
        createdAt: _ago(40),
        updatedAt: _ago(4),
        files: _files('inspection', 'internal', count: 5),
        uses: 3,
      ),
      Dataset(
        namespace: 'jdoe',
        slug: 'scratch',
        title: 'Scratch',
        level: 'public',
        ownerId: 'jdoe',
        createdAt: _ago(2),
      ),
      // Not listed for jdoe: cleared to CONFIDENTIAL, and not in the audience.
      Dataset(
        namespace: 'ops',
        slug: 'security-assessments-2026',
        title: 'Security assessments 2026',
        level: 'restricted',
        ownerId: 'bnguyen',
        createdAt: _ago(30),
        files: _files('assessment', 'restricted', count: 9),
        audience: {'g-plant-shift'},
      ),
      Dataset(
        namespace: 'eng',
        slug: 'compressor-overhaul-planning',
        title: 'Compressor overhaul planning',
        level: 'internal',
        ownerId: 'cgarcia',
        createdAt: _ago(80),
        files: _files('overhaul', 'internal', count: 14),
        audience: {'g-eng-reliability'},
      ),
    ];

/// About a hundred more, so the catalog has to be searched rather than
/// scrolled. Seeded, so the list is the same on every run.
List<Dataset> _generated() {
  final random = math.Random(7);
  const systems = [
    'P-100',
    'P-200',
    'C-300',
    'T-400',
    'G-500',
    'B-600',
    'H-700',
    'V-800',
  ];
  const topics = [
    'controls',
    'seals',
    'motors',
    'valves',
    'lubrication',
    'bearings',
    'corrosion control',
    'NDT',
    'structures',
    'electrical',
    'instrumentation',
    'cooling',
  ];
  const orgs = [
    ('ops', 'asmith', 'Ops › Logistics', {'g-ops-logistics'}),
    ('plant', 'erivera', 'Ops › Plant › Maintenance', {'g-plant-mx'}),
    ('plant', 'bnguyen', 'Ops › Plant › Shift team', {'g-plant-shift'}),
    (
      'eng',
      'cgarcia',
      'Eng › Reliability',
      {'g-ops-logistics', 'g-eng-reliability'},
    ),
  ];
  const levels = ['public', 'internal', 'internal', 'internal', 'confidential'];
  final result = <Dataset>[];
  for (var i = 0; i < 100; i++) {
    final system = systems[i % systems.length];
    final topic = topics[(i * 5) % topics.length];
    final (ns, owner, affiliation, audience) = orgs[i % orgs.length];
    final level = levels[random.nextInt(levels.length)];
    final count = 3 + random.nextInt(60);
    final ingesting = random.nextInt(9) == 0;
    final slug = '${system.toLowerCase()}-${topic.replaceAll(' ', '-')}'
        '-${(i ~/ (systems.length * 2)) + 1}';
    result.add(
      Dataset(
        namespace: ns,
        slug: slug,
        title: '$system ${topic[0].toUpperCase()}${topic.substring(1)} '
            'references',
        description: '$topic material for the $system units.',
        level: level,
        ownerId: owner,
        createdAt: _ago(30 + random.nextInt(900)),
        updatedAt: _ago(1 + random.nextInt(200)),
        files: _files(
          slug,
          level,
          count: count,
          rawOnly: random.nextInt(4) == 0 ? random.nextInt(count ~/ 2 + 1) : 0,
          done: ingesting ? count ~/ 3 : null,
        ),
        audience: audience,
        tags: DatasetTags(
          keywords: {topic, if (i.isEven) 'service manuals'},
          systems: {system},
          affiliations: {affiliation},
        ),
        uses: random.nextInt(150),
      ),
    );
  }
  return result;
}

/// The store the datasets mockup opens on. Fresh each call, so a hot restart
/// starts over.
DatasetsStore sampleStore() => DatasetsStore(
      user: _user,
      principals: _principals,
      datasets: [..._handcrafted(), ..._generated()],
      orgNamespaces: const ['ops', 'plant', 'eng'],
      presets: presets,
      pinned: {'ops/maintenance-trend-data'},
      trays: const {
        'pump-pressure': ['ops/pump-service-manuals', 'jdoe/pump-quickref'],
        'peak-plan': [
          'plant/shift-planning-playbook',
          'plant/outage-planning-library',
        ],
      },
    );

/// The rooms behind the presets, with a conversation in two of them.
StaticSoliplexApi datasetsApi() {
  final today = DateTime.now();
  final yesterday = today.subtract(const Duration(days: 1));
  DateTime at(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute).toUtc();

  ThreadHistory exchange(String id, String question, String answer) =>
      ThreadHistory(
        messages: [
          TextMessage(
            id: 'u-$id',
            user: ChatUser.user,
            createdAt: at(yesterday, 9, 0),
            text: question,
          ),
          TextMessage(
            id: 'a-$id',
            user: ChatUser.assistant,
            createdAt: at(yesterday, 9, 1),
            text: answer,
          ),
        ],
        messageStates: {
          'a-$id': MessageState(
            userMessageId: 'u-$id',
            sourceReferences: const [],
            runId: 'run-$id',
          ),
        },
      );

  return StaticSoliplexApi(
    rooms: [
      for (final p in presets)
        Room(
          id: p.roomId,
          name: p.name,
          description: p.description,
          welcomeMessage: 'Ask about the datasets this thread uses — check '
              'them in the thread panel before you send: they are fixed '
              'once the conversation starts.',
          suggestions: switch (p.roomId) {
            'plant-mx' => const [
                'Pump pressure drops after start-up — where do I start?',
                'Which relief valve inspections are due this month?',
              ],
            'ops-planning' => const ['Draft a peak-demand staffing timeline'],
            _ => const ['Summarise the latest safety bulletins'],
          },
          acceptsThreadUploads: true,
        ),
    ],
    threads: {
      'plant-mx': [
        ThreadInfo(
          id: 'pump-pressure',
          roomId: 'plant-mx',
          name: 'Pump pressure troubleshooting',
          createdAt: at(yesterday, 9, 0),
          lastActivity: at(yesterday, 9, 1),
        ),
      ],
      'ops-planning': [
        ThreadInfo(
          id: 'peak-plan',
          roomId: 'ops-planning',
          name: 'Peak demand plan draft',
          createdAt: at(yesterday, 14, 0),
          lastActivity: at(yesterday, 14, 5),
        ),
      ],
      'public-research': [],
    },
    histories: {
      'pump-pressure': exchange(
        'pump',
        'P-100 discharge pressure drops slowly after start-up. Where do I '
            'start?',
        'Start with the fault-isolation tree for slow pressure decay in the '
            'pump service manuals: check the suction strainer first, then the '
            'seal leak-off flow. Your quick reference notes the same order.',
      ),
      'peak-plan': exchange(
        'peak',
        'Outline a 72-hour peak-demand staffing plan.',
        'Following the playbook: split the peak into three 24-hour blocks, '
            'front-loading the shift handovers. The outage planning library '
            'is still ingesting, so I read its raw files without search.',
      ),
    },
  );
}
