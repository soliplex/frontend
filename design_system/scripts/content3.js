/* Soliplex Design System — content part 3:
   Execution timeline, Citations, Document picker, Network inspector, Quiz question */

/* Re-use codeBlock / demoBlock already defined in content2.js */

const executionDemo = `
  <div class="demo-col" style="gap:0;">
    <div class="m-exec-step done">
      <div class="m-exec-rail"><span class="m-exec-dot"></span></div>
      <div class="m-exec-body">
        <div class="m-exec-head">
          <span class="m-exec-label">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>
            plan
          </span>
          <span class="m-exec-meta">0.18s</span>
        </div>
        <div class="m-exec-detail">Decompose question into two retrieval subqueries.</div>
      </div>
    </div>

    <div class="m-exec-step done">
      <div class="m-exec-rail"><span class="m-exec-dot"></span></div>
      <div class="m-exec-body">
        <div class="m-exec-head">
          <span class="m-exec-label">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>
            search.documents
          </span>
          <span class="m-exec-meta">0.92s · 4 hits</span>
        </div>
        <div class="m-exec-detail">
          <span class="m-exec-kv"><span class="k">query</span><span class="v">amoxicillin pediatric AOM dose</span></span>
          <span class="m-exec-kv"><span class="k">top_k</span><span class="v">4</span></span>
        </div>
      </div>
    </div>

    <div class="m-exec-step running">
      <div class="m-exec-rail"><span class="m-exec-dot"></span></div>
      <div class="m-exec-body">
        <div class="m-exec-head">
          <span class="m-exec-label">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v4"/><path d="M12 18v4"/><path d="M4.93 4.93l2.83 2.83"/><path d="M16.24 16.24l2.83 2.83"/><path d="M2 12h4"/><path d="M18 12h4"/><path d="M4.93 19.07l2.83-2.83"/><path d="M16.24 7.76l2.83-2.83"/></svg>
            synthesize
          </span>
          <span class="m-exec-meta">streaming…</span>
        </div>
        <div class="m-exec-detail">Writing answer &mdash; 187 tokens so far.</div>
      </div>
    </div>

    <div class="m-exec-step pending">
      <div class="m-exec-rail"><span class="m-exec-dot"></span></div>
      <div class="m-exec-body">
        <div class="m-exec-head">
          <span class="m-exec-label">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>
            cite.passages
          </span>
          <span class="m-exec-meta">queued</span>
        </div>
      </div>
    </div>
  </div>`;

const execution = demoBlock("execution", "Execution timeline",
  executionDemo,
  "lib/src/modules/room/ui/execution_timeline.dart (excerpt)",
  `enum ExecStepState { pending, running, done, failed }

class ExecutionStep extends StatelessWidget {
  const ExecutionStep({
    super.key,
    required this.label,
    required this.state,
    this.detail,
    this.duration,
    this.isLast = false,
  });

  final String label;
  final ExecStepState state;
  final String? detail;
  final Duration? duration;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dotColor = switch (state) {
      ExecStepState.done    => colors.primary,
      ExecStepState.running => colors.primary,
      ExecStepState.failed  => colors.error,
      ExecStepState.pending => colors.outlineVariant,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(children: [
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: state == ExecStepState.running
                      ? Colors.transparent : dotColor,
                  border: Border.all(color: dotColor, width: 2),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(child: VerticalDivider(
                  color: colors.outlineVariant, width: 1)),
            ]),
          ),
          // …label, meta, detail rows…
        ],
      ),
    );
  }
}`
);

/* ---------- citations ---------- */

const citationsDemo = `
  <div class="m-cite-answer">
    The guideline recommends <strong>80–90 mg/kg/day</strong> of amoxicillin
    divided BID for uncomplicated acute otitis media<sup class="m-cite-ref">1</sup>.
    For a 22 kg child this works out to roughly 880 mg twice daily, continued
    for 10 days in children under 6<sup class="m-cite-ref">2</sup>.
  </div>
  <div class="m-cite-sources">
    <div class="m-cite-head">Sources · 2 citations</div>

    <div class="m-cite-card">
      <div class="m-cite-num">1</div>
      <div class="m-cite-meta">
        <div class="title">AAP · Clinical practice guideline: The diagnosis and management of AOM</div>
        <div class="where">guidelines.pdf · p.&nbsp;e974 · §Treatment</div>
        <div class="quote">"Amoxicillin at 80 to 90 mg/kg/day in two divided doses is recommended as first-line therapy."</div>
      </div>
      <button class="m-icon-btn" aria-label="Open source">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17L17 7"/><path d="M8 7h9v9"/></svg>
      </button>
    </div>

    <div class="m-cite-card">
      <div class="m-cite-num">2</div>
      <div class="m-cite-meta">
        <div class="title">Red Book · 32nd ed. · Otitis media</div>
        <div class="where">red-book-2021.pdf · p.&nbsp;658</div>
        <div class="quote">"Duration of therapy is 10 days for children younger than 6 years…"</div>
      </div>
      <button class="m-icon-btn" aria-label="Open source">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17L17 7"/><path d="M8 7h9v9"/></svg>
      </button>
    </div>
  </div>`;

const citations = demoBlock("citations", "Citations",
  citationsDemo,
  "lib/src/modules/room/ui/citation_ref.dart",
  `/// Superscript reference anchored inside markdown output.
class CitationRef extends StatelessWidget {
  const CitationRef({super.key, required this.index, required this.onTap});
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Transform.translate(
        offset: const Offset(0, -4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$index',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}`
);

/* ---------- document picker ---------- */

const docPickerDemo = `
  <div class="m-picker">
    <div class="m-picker-head">
      <div class="m-picker-title">Attach documents</div>
      <div class="m-picker-sub">Responses will only draw from documents you select.</div>
    </div>
    <div class="m-picker-search">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>
      <input class="m-picker-input" placeholder="Search 142 documents…" />
      <div class="m-picker-filters">
        <span class="m-chip selected">pdf</span>
        <span class="m-chip">md</span>
        <span class="m-chip">notes</span>
      </div>
    </div>

    <div class="m-picker-list">
      <label class="m-picker-row selected">
        <input type="checkbox" checked />
        <div class="m-picker-icon pdf">PDF</div>
        <div class="m-picker-meta">
          <div class="name">AAP clinical practice guideline — AOM</div>
          <div class="sub">guidelines/aap-aom-2013.pdf · 14 pages · added Mar 2</div>
        </div>
        <span class="m-badge">indexed</span>
      </label>

      <label class="m-picker-row selected">
        <input type="checkbox" checked />
        <div class="m-picker-icon md">MD</div>
        <div class="m-picker-meta">
          <div class="name">Triage protocol — v3</div>
          <div class="sub">runbooks/triage-protocol.md · 2,148 tokens · updated 4d ago</div>
        </div>
        <span class="m-badge">indexed</span>
      </label>

      <label class="m-picker-row">
        <input type="checkbox" />
        <div class="m-picker-icon pdf">PDF</div>
        <div class="m-picker-meta">
          <div class="name">Red Book — 32nd edition (excerpts)</div>
          <div class="sub">reference/red-book-2021.pdf · 41 pages · added Feb 19</div>
        </div>
        <span class="m-badge">indexed</span>
      </label>

      <label class="m-picker-row disabled">
        <input type="checkbox" disabled />
        <div class="m-picker-icon pdf">PDF</div>
        <div class="m-picker-meta">
          <div class="name">Antibiotic stewardship bulletin — Q1</div>
          <div class="sub">bulletins/q1-2026.pdf · 3 pages</div>
        </div>
        <span class="m-badge pending">re-indexing</span>
      </label>
    </div>

    <div class="m-picker-foot">
      <div class="m-picker-count">2 of 142 selected</div>
      <div class="demo-row" style="gap:8px;">
        <button class="m-btn m-btn-text">Cancel</button>
        <button class="m-btn m-btn-filled">Attach 2 docs</button>
      </div>
    </div>
  </div>`;

const docPicker = demoBlock("docpicker", "Document picker",
  docPickerDemo,
  "lib/src/modules/room/ui/document_picker_sheet.dart (excerpt)",
  `class DocumentPickerSheet extends ConsumerWidget {
  const DocumentPickerSheet({super.key, required this.room});
  final Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(roomDocumentsProvider(room.id));
    final selected = ref.watch(pickerSelectionProvider);
    final query = ref.watch(pickerQueryProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      builder: (ctx, scroll) => Column(children: [
        _PickerHeader(total: docs.length),
        _PickerSearch(query: query),
        Expanded(child: ListView.builder(
          controller: scroll,
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i];
            return CheckboxListTile(
              value: selected.contains(d.id),
              title: Text(d.name),
              subtitle: Text(d.path, overflow: TextOverflow.ellipsis),
              secondary: _DocIcon(kind: d.kind),
              onChanged: d.isIndexed
                  ? (v) => ref.read(pickerSelectionProvider.notifier).toggle(d.id)
                  : null,
            );
          },
        )),
        _PickerFooter(selected: selected, total: docs.length),
      ]),
    );
  }
}`
);

/* ---------- network inspector ---------- */

const networkDemo = `
  <div class="m-net">
    <div class="m-net-toolbar">
      <span class="m-chip selected">All</span>
      <span class="m-chip">Retrieval</span>
      <span class="m-chip">LLM</span>
      <span class="m-chip">Auth</span>
      <div style="flex:1"></div>
      <span class="m-net-kpi"><span class="k">p50</span><span class="v">214ms</span></span>
      <span class="m-net-kpi"><span class="k">p95</span><span class="v">1.18s</span></span>
    </div>
    <table class="m-net-table">
      <thead>
        <tr><th>#</th><th>Method</th><th>Endpoint</th><th>Status</th><th>Latency</th><th>Size</th></tr>
      </thead>
      <tbody>
        <tr class="m-net-row">
          <td class="num">01</td>
          <td><span class="m-net-method get">GET</span></td>
          <td class="path">/v1/rooms/medical-rag/documents</td>
          <td><span class="m-net-status s2">200</span></td>
          <td class="num">142ms</td>
          <td class="num">38.2 kB</td>
        </tr>
        <tr class="m-net-row">
          <td class="num">02</td>
          <td><span class="m-net-method post">POST</span></td>
          <td class="path">/v1/search/embeddings</td>
          <td><span class="m-net-status s2">200</span></td>
          <td class="num">214ms</td>
          <td class="num">6.1 kB</td>
        </tr>
        <tr class="m-net-row expanded">
          <td class="num">03</td>
          <td><span class="m-net-method post">POST</span></td>
          <td class="path">/v1/threads/3a7e/messages</td>
          <td><span class="m-net-status s2">200</span></td>
          <td class="num">1.18s</td>
          <td class="num">streaming</td>
        </tr>
        <tr class="m-net-detail">
          <td></td>
          <td colspan="5">
            <div class="m-net-kv-grid">
              <div><span class="k">request_id</span><span class="v">req_01HXA7…P4B</span></div>
              <div><span class="k">model</span><span class="v">claude-sonnet-4.5</span></div>
              <div><span class="k">stream</span><span class="v">true</span></div>
              <div><span class="k">ttfb</span><span class="v">312ms</span></div>
              <div><span class="k">tokens.in</span><span class="v">2,184</span></div>
              <div><span class="k">tokens.out</span><span class="v">417</span></div>
            </div>
          </td>
        </tr>
        <tr class="m-net-row">
          <td class="num">04</td>
          <td><span class="m-net-method get">GET</span></td>
          <td class="path">/v1/citations/resolve?passage=…</td>
          <td><span class="m-net-status s4">404</span></td>
          <td class="num">88ms</td>
          <td class="num">312 B</td>
        </tr>
        <tr class="m-net-row">
          <td class="num">05</td>
          <td><span class="m-net-method post">POST</span></td>
          <td class="path">/v1/feedback</td>
          <td><span class="m-net-status s5">503</span></td>
          <td class="num">30.00s</td>
          <td class="num">—</td>
        </tr>
      </tbody>
    </table>
  </div>`;

const network = demoBlock("network", "Network inspector",
  networkDemo,
  "lib/src/modules/diagnostics/ui/network_inspector_page.dart (excerpt)",
  `class NetworkInspectorPage extends ConsumerWidget {
  const NetworkInspectorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(httpTapProvider);
    final filter = ref.watch(httpFilterProvider);
    final rows = events.where(filter.matches).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: Column(children: [
        const _FilterBar(),
        Expanded(
          child: DataTable2(
            columns: const [
              DataColumn2(label: Text('#'),       size: ColumnSize.S),
              DataColumn2(label: Text('Method'),  size: ColumnSize.S),
              DataColumn2(label: Text('Endpoint')),
              DataColumn2(label: Text('Status'),  size: ColumnSize.S),
              DataColumn2(label: Text('Latency'), size: ColumnSize.S),
              DataColumn2(label: Text('Size'),    size: ColumnSize.S),
            ],
            rows: rows.map((e) => DataRow2(
              onTap: () => ref.read(httpSelectionProvider.notifier).state = e.id,
              cells: [
                DataCell(Text(e.index.toString())),
                DataCell(MethodChip(method: e.method)),
                DataCell(Text(e.path, overflow: TextOverflow.ellipsis)),
                DataCell(StatusChip(code: e.status)),
                DataCell(Text(e.latency.inMillisFormatted)),
                DataCell(Text(e.bytes.humanBytes)),
              ],
            )).toList(),
          ),
        ),
      ]),
    );
  }
}`
);

/* ---------- quiz question ---------- */

const quizDemo = `
  <div class="m-quiz">
    <div class="m-quiz-head">
      <span class="m-badge">Quiz · Triage v3</span>
      <span class="m-quiz-progress"><span class="bar" style="width:60%"></span></span>
      <span class="m-quiz-count">3 / 5</span>
    </div>
    <div class="m-quiz-prompt">
      A 22 kg child presents with a 3-day fever and unilateral otalgia. Otoscopy shows
      a bulging tympanic membrane with purulent effusion. Which is the recommended
      first-line antibiotic regimen?
    </div>
    <div class="m-quiz-choices">
      <label class="m-quiz-choice">
        <span class="m-quiz-letter">A</span>
        <span class="m-quiz-text">Azithromycin 10 mg/kg once daily for 5 days.</span>
      </label>
      <label class="m-quiz-choice correct">
        <span class="m-quiz-letter">B</span>
        <span class="m-quiz-text">Amoxicillin 80–90 mg/kg/day divided BID for 10 days.</span>
        <span class="m-quiz-mark ok">✓</span>
      </label>
      <label class="m-quiz-choice picked wrong">
        <span class="m-quiz-letter">C</span>
        <span class="m-quiz-text">Ceftriaxone 50 mg/kg IM, single dose.</span>
        <span class="m-quiz-mark no">×</span>
      </label>
      <label class="m-quiz-choice">
        <span class="m-quiz-letter">D</span>
        <span class="m-quiz-text">Watchful waiting for 72 hours, no antibiotics.</span>
      </label>
    </div>
    <div class="m-quiz-explain">
      <div class="head">Why B</div>
      <p>
        Amoxicillin at 80–90 mg/kg/day is first-line for uncomplicated AOM in children
        without recent β-lactam exposure. Ceftriaxone is reserved for treatment failure
        or inability to tolerate oral therapy.
      </p>
      <div class="refs">
        <span class="m-chip">guidelines.pdf · p.&nbsp;e974</span>
        <span class="m-chip">red-book-2021.pdf · p.&nbsp;658</span>
      </div>
    </div>
    <div class="m-quiz-foot">
      <button class="m-btn m-btn-text">Skip</button>
      <button class="m-btn m-btn-filled">Next question</button>
    </div>
  </div>`;

const quiz = demoBlock("quiz", "Quiz question",
  quizDemo,
  "lib/src/modules/quiz/ui/question_card.dart (excerpt)",
  `enum ChoiceState { idle, picked, correct, wrong }

class QuestionCard extends ConsumerWidget {
  const QuestionCard({super.key, required this.question});
  final QuizQuestion question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer = ref.watch(answerProvider(question.id));
    final theme = Theme.of(context);

    Color bgFor(ChoiceState s) => switch (s) {
      ChoiceState.correct => theme.colorScheme.success.withAlpha(30),
      ChoiceState.wrong   => theme.colorScheme.errorContainer,
      ChoiceState.picked  => theme.colorScheme.primary.withAlpha(20),
      ChoiceState.idle    => theme.colorScheme.surfaceContainerLow,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QuizHeader(question: question),
            const SizedBox(height: SoliplexSpacing.s3),
            Text(question.prompt, style: theme.textTheme.titleMedium),
            const SizedBox(height: SoliplexSpacing.s4),
            for (final c in question.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
                child: ChoiceTile(
                  choice: c,
                  state: answer.stateFor(c),
                  onTap: () => ref.read(answerProvider(question.id).notifier).pick(c),
                ),
              ),
            if (answer.revealed) ExplanationPanel(question: question),
          ],
        ),
      ),
    );
  }
}`
);

window.__SECTIONS_3 = { execution, citations, docPicker, network, quiz };
