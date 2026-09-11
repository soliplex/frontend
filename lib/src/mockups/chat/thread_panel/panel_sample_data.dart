import '../context_usage.dart';
import 'panel_state.dart';

/// The thread panel's opening state: a couple of databases already connected,
/// basic skills auto-loaded, a third of the window used.
ThreadPanelState samplePanelState() => ThreadPanelState(
      contextUsage: const ContextUsage(
        tokens: 41200,
        byShare: {
          ContextShare.human: 6400,
          ContextShare.llm: 14800,
          ContextShare.system: 5200,
          ContextShare.rag: 12600,
          ContextShare.tools: 2200,
        },
        contextWindow: 128000,
        isExact: true,
      ),
      databases: [
        const RagDatabase(
          id: 'papers',
          name: 'Retrieval papers',
          description: 'Forty-one papers on dense and sparse retrieval, '
              '2019–2025, chunked by section with figures extracted.',
          documentCount: 41,
          status: DbStatus.connected,
        ),
        const RagDatabase(
          id: 'surveys',
          name: 'Survey collection',
          description: 'Long-form surveys and tutorials. Coarser chunks; '
              'good for background, poor for specific numbers.',
          documentCount: 9,
          status: DbStatus.connected,
        ),
        const RagDatabase(
          id: 'benchmarks',
          name: 'Benchmark results',
          description: 'Leaderboard snapshots for BEIR, MS MARCO and NQ, '
              'one document per model per date.',
          documentCount: 312,
        ),
        const RagDatabase(
          id: 'internal',
          name: 'Internal experiment notes',
          description: 'Lab notebooks from the last two quarters. Contains '
              'unpublished numbers — check before quoting.',
          documentCount: 128,
        ),
        const RagDatabase(
          id: 'code',
          name: 'Reference implementations',
          description: 'Source trees for the retrievers discussed in the '
              'papers, indexed by file.',
          documentCount: 2044,
          status: DbStatus.indexing,
        ),
        const RagDatabase(
          id: 'archive',
          name: 'Pre-2019 archive',
          description: 'Older IR literature. The index is being rebuilt '
              'after a schema change.',
          documentCount: 560,
          status: DbStatus.unavailable,
        ),
        for (var i = 1; i <= 12; i++)
          RagDatabase(
            id: 'shard-$i',
            name: 'Crawl shard $i',
            description: 'Web crawl slice $i of 12. Mixed quality; useful '
                'for recall, not for citations.',
            documentCount: 5000 + i * 137,
          ),
      ],
      skills: const [
        AgentSkill(
          id: 'cite',
          name: 'Cite passages',
          description: 'Quotes the passages an answer draws on and links '
              'each to its document.',
          tier: SkillTier.basic,
          tokens: 600,
        ),
        AgentSkill(
          id: 'tables',
          name: 'Tabulate results',
          description: 'Renders comparable numbers as a table instead of '
              'prose.',
          tier: SkillTier.basic,
          tokens: 450,
        ),
        AgentSkill(
          id: 'glossary',
          name: 'Expand acronyms',
          description: 'Expands IR acronyms on first use.',
          tier: SkillTier.basic,
          tokens: 300,
        ),
        AgentSkill(
          id: 'critique',
          name: 'Methodology critique',
          description: 'Reads a paper\'s experimental setup against a '
              'checklist — baselines, seeds, held-out data, ablations — and '
              'flags what is missing. Adds a long rubric to the prompt.',
          tier: SkillTier.advanced,
          tokens: 3800,
        ),
        AgentSkill(
          id: 'replicate',
          name: 'Replication plan',
          description: 'Drafts a step-by-step plan to reproduce a reported '
              'result using the connected reference implementations.',
          tier: SkillTier.advanced,
          tokens: 2900,
        ),
        AgentSkill(
          id: 'related',
          name: 'Related-work sweep',
          description: 'Searches every connected database for work the '
              'current paper should have cited, ranked by overlap.',
          tier: SkillTier.advanced,
          tokens: 2200,
        ),
        AgentSkill(
          id: 'latex',
          name: 'LaTeX export',
          description: 'Writes answers in LaTeX with a bibliography block '
              'for the cited documents.',
          tier: SkillTier.advanced,
          tokens: 1700,
        ),
      ],
      initialRecipients: const ['erik', 'ana'],
      contacts: const [
        WorkspaceContact(id: 'erik', name: 'Erik Lindqvist'),
        WorkspaceContact(id: 'ana', name: 'Ana Moreau'),
        WorkspaceContact(id: 'tomas', name: 'Tomás Ferreira'),
        WorkspaceContact(id: 'priya', name: 'Priya Natarajan'),
        WorkspaceContact(id: 'jonas', name: 'Jonas Weber'),
      ],
      documents: const [
        WorkspaceDocument(
            id: 'doc-1', title: 'Dense Passage Retrieval Revisited'),
        WorkspaceDocument(id: 'doc-2', title: 'A Survey of Neural Retrieval'),
        WorkspaceDocument(
            id: 'doc-3', title: 'Evaluating Retrieval-Augmented Generation'),
      ],
    );
