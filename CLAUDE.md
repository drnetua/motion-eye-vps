# CLAUDE.md

Guidance for Claude Code in this repository.

## Decisions log rule

`docs/decisions.md` is append-only and is the contract between tasks.

1. **When to write.** Any time a decision is made that a later task could otherwise re-litigate: in an explore session, a proposal, a design, a code review, or when implementation deviates from a design. Append it in the same session or the same change. A change whose design introduces a decision is not done until the entry exists.
2. **One entry per decision**, numbered `D-NN` in order of appearance. Never renumber, never delete. A changed decision gets a **new** entry with `Supersedes: D-NN`, and the old entry's header line gets `· Superseded by: D-MM`.
3. **Be precise, not general.** Name the module, table, column, endpoint, env var, limit with its unit, and the exact scope. "Use a simpler approach" or "handle it later" is not an entry. If a number is a default that may change, say where it is configured.
4. **Always say why.** `Why:` states the concrete reason: a constraint, a cost, a proven precedent, a risk. Add `Accepted cost:` whenever the decision gives something up. A reader who disagrees must be able to see what would have to change for the decision to flip.
5. **Reference, don't restate.** OpenSpec proposals and designs cite `D-NN` instead of copying the text, and name any `D-NN` they would supersede.

Entry format:

```
## D-NN — <decision in one sentence>
Date: YYYY-MM-DD · Scope: <modules / pages> · Supersedes: <D-MM or —>
Decision: <precise statement: names, numbers with units, boundaries>
Why: <concrete reason>
Accepted cost: <what is given up, or omit the line>
```
