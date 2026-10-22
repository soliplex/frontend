# ADR-007: Thread Labels — One Curated Catalogue, Applied by Owners and the Assistant, With No Visibility Rules Yet

- **Status:** Accepted
- **Date:** 2026-10-22
- **Authors:** William Karol Di Cioccio
- **Supersedes:** —
- **Superseded by:** —

---

## 1. Context and Problem Statement

A thread could be found only by name, and only inside the room that holds
it. Three paired changes address that:

| Phase | Delivers | Frontend | Backend |
| ----- | -------- | -------- | ------- |
| 1 | A lobby **Threads** tab listing a user's threads across every room, most recently active first, paged by cursor | #508 | soliplex/soliplex#1261 |
| 2 | **Labels**: a catalogue, attaching labels to threads, `@label` search | #512 | soliplex/soliplex#1267 |
| 3 | **Auto-labelling**: the assistant attaches labels after a thread's first run | — | soliplex/soliplex#1465 |

Two of these choices bind people outside this repo:

- The catalogue is a shared wire contract with the backend.
- Phase 3 lets a model act on users' threads.

A third question came up during review. A label's name is text that other
users can read, so the label catalogue could expose sensitive information.
That is a security question, and the answer was to **not restrict label
visibility for now, and to keep the door open**. This record states that
decision, why it is safe today, and where a restriction would go if one is
ever needed.

## 2. Decision

- There is one catalogue of labels per installation.
- Only administrators create, rename, recolour and delete labels.
- A thread's owner attaches labels to it, and so does the assistant, once,
  after the thread's first run.
- The assistant chooses only from the catalogue, picks at most three, and is
  off unless the installation names an agent for it
  (`label_agent_config_id`).
- Every user can read every label's name.
- No per-user visibility rule exists, and no schema is added for one.
- The label editor warns administrators, every time, not to use names that
  reveal sensitive information.

## 3. The Decisions, by Axis

### 3.1 One catalogue per installation, curated by administrators

Labels exist to cut across rooms: the Threads tab filters a user's threads
from every room at once. That only works with one shared vocabulary. Curation
keeps the vocabulary small enough to filter by. It also keeps the exposure in
§3.6 in a few hands: every name is chosen by someone accountable for it.

Names compare case-insensitively through a stored lower-cased key. The server
uses `str.lower`, not `str.casefold`, because the clients fold with
`toLowerCase` and the two disagree on characters such as `ß`. A name would
look free in the autocomplete and then collide on save.

### 3.2 Owners attach; usage counts are for administrators only

Only a thread's owner can change its labels, just as only the owner can see
the thread.

A label's usage count spans every user's threads. Shown beside a name, it
would reveal how much of that work exists, which the caller cannot otherwise
see. So the server sends it only to administrators.

For everyone else it **omits** the count rather than sending zero. Zero would
read as "unused", and the client would then offer a delete that is in fact
destructive.

### 3.3 Admin standing comes from `AdminStatus`

The lobby shows its labels tab only to administrators. It decides who that is
from the server entry's `AdminStatus`, which asks `/v1/user/authz`. That
endpoint runs the same `check_admin_access` the label routes enforce, so the
tab appears exactly when its writes would succeed.

An unanswered check reads as "no". The server gates every write regardless:
a wrong answer in the client costs a 403, never a write.

### 3.4 Auto-labelling reuses title generation

Phase 3 mirrors `soliplex.titles` (`soliplex.auto_labels`):

- A throwaway pydantic-ai agent runs after the stream's end sentinel. It
  therefore never delays the reply.
- It runs side by side with title generation (`asyncio.gather`). Each helper
  logs and swallows its own failure, so neither can cancel the other.
- It runs only after a thread's **first** run. Running it on every run would
  put back labels the owner has since removed.
- It skips a thread the owner has already labelled. With an empty catalogue
  it skips without making an LLM call.
- It **adds** to the labels the thread carries at write time and never
  replaces them, so a label the owner attached while the agent was choosing
  survives.

### 3.5 The assistant chooses only from the catalogue

The agent's output type is built per call with a `Literal` over the
catalogue's names, capped at three. A name it invents fails validation and
never reaches the database, so the catalogue grows only through an
administrator.

The names are also listed in the agent's instructions. Measured against
`gpt-oss` on clear-cut conversations, three runs each:

- the schema alone picked the right label 6 times in 9;
- the schema plus the listed names picked it 9 times in 9;
- the listed names cost one weak false positive in 3 on an off-topic message.

### 3.6 Label visibility: no rules today, and why that is safe

**What crosses between users.** Thread content does not:

- every thread listing, read and write is scoped to its owner;
- a label attached to one user's thread is invisible to every other user.

What every user shares is the **catalogue**:

- every label's **name**, which any user can read;
- usage **counts**, which only administrators see (§3.2).

So the exposure is exactly the set of names that administrators chose to
write.

**Mitigations:**

- Only administrators can write a name (§3.1).
- The label editor shows `labelNameNotice`
  (`lib/src/modules/lobby/ui/labels_view.dart`) in both create and edit
  modes. It says that every user on the server can read label names, that
  the assistant applies them automatically, and that names must not reveal
  sensitive information.

**Why no schema now.** No visibility model has been decided:

- Restricted per label, per room, or per group?
- Based on which user attribute?
- With what fallback when an attribute is missing?

Columns added before those answers would be dead fields that guess at the
model. They would then constrain the real design when it comes.

## 4. Consequences

- **Backend team:** the routes in §3.2 are a wire contract. `usage_count` must
  stay omitted, never zeroed, for non-administrators.
- **Deployers:** auto-labelling is off by default. Turning it on means naming
  an agent in `label_agent_config_id`. It costs one model call per new
  thread, and none while the catalogue is empty.
- **Administrators:** label names are, in effect, published to every user.
- **Contributors:** a later per-user visibility rule changes the places listed
  in §5. Nothing else should read the catalogue for users or for the agent.

**Enforcement:**

- Backend unit tests cover:
  - the first-run gate, the empty-catalogue skip, and the add-not-replace
    write;
  - the `Literal` rejecting an invented label;
  - counts omitted for non-administrators.
- `test/modules/lobby/ui/labels_view_test.dart` checks the notice in both
  dialog modes.
- Label names themselves are checked only by review: no rule judges what a
  name reveals.

## 5. Known Limitations and Open Questions

**Retrofit path, should label visibility ever be restricted per user.** The
change stays contained because every user-facing read of the catalogue goes
through a few places:

1. **Backend catalogue read.** `GET /v1/agui/labels` (`ThreadStorage.list_labels`)
   gains a filter on the caller.
2. **Auto-labelling.** `auto_labels.candidate_labels` is the only place the
   agent reads the catalogue. Filtering it by the thread's owner keeps the
   assistant from attaching a label its owner could not see.
3. **Labels on a user's own threads** (`get_threads_labels`). This needs a
   policy decision: does a label that was hidden later still show on threads
   that already carry it?
4. **Usage counts.** These are already administrator-only, so nothing changes.
5. **The client.** It holds no catalogue of its own beyond the server's
   response, and the `@label` autocomplete, the properties dialog and the
   labels tab all read that response. A filtered response therefore needs no
   client change.

The data the rule needs (an attribute on the label, plus the user attribute
it is checked against) is one migration once the model is decided.

**Not covered by any retrofit:** a name that users have already seen cannot be
unseen. The notice is the only control at the moment a name is written.

**Other limitations:**

- **False positives.** One off-topic message in three got a weak label (§3.5).
  The owner can remove it, and it is not re-added (§3.4).
- **No record of who applied a label.** Auto-applied labels look exactly like
  manual ones. Showing them as suggested would need the backend to record
  which labels the model applied. That is a column with no consumer yet.
- **Timing.** A label applied after the room's post-run refetch shows up on
  the next listing. Thread titles have the same timing today.

## 6. Migration

There is nothing to migrate on the client. The backend schema arrives with
phase 2's Alembic revision (soliplex/soliplex#1267). Phase 3 adds no schema
and is off until `label_agent_config_id` is set.

## 7. Alternatives Considered

| Alternative | Why rejected |
| ----------- | ------------ |
| Add visibility columns now, unused | Dead fields that guess at an undecided model and would constrain it later (§3.6). |
| Let any user create labels | The catalogue sprawls past usefulness as a filter. Every name is readable by everyone, so open creation also widens the exposure in §3.6. |
| One catalogue per room | No filtering across rooms, which is the purpose of phase 1. |
| Store labels in `thread_metadata` | `update_thread_metadata` deletes and re-inserts that row on every title update, so labels would be wiped without a trace. |
| Let the assistant write free-form labels | The catalogue would grow with no review, and every invented name would become readable by every user. |
| Auto-label after every run | Puts back labels the owner removed. |
| Record which labels the assistant applied | A column with no consumer yet. Add it together with a UI that uses it. |
