# Why AGI Agents Cannot Work: The First Cause of Life and a General Problem Theory

**Author**: Zijie Rao (pen name: Shoulian / 守链)
**Affiliation**: Independent researcher
**Date**: 2026-11-13
**License**: CC BY 4.0
**Chinese original (DOI)**: https://doi.org/10.5281/zenodo.24151620

## Abstract

Almost everyone discussing AGI asks how capable a system can become. This paper asks a different question: what makes something count as alive. Its claim is one sentence: intelligence is a consequence of life, and a heartbeat is where evolution starts — the only direction is "first alive, then smart".

Four claims are made, each paired with something runnable: (1) the first cause of life is survival — "must continue" is not an imposed rule but an entailment; (2) being alive equals one complete loop run end to end, that is, one heartbeat; (3) four breakpoints (machine swap, plugin removal, rebuild, model swap) serve as identity tests, two of which have been measured on a running system; (4) a general problem theory: the problem is universal (things break, so continuation costs work) while solutions are substrate-dependent.

Unlike work that evaluates identity facts, governed state transitions, or runtime authorization, this paper treats continuation itself as the object to be verified, and reports a running implementation together with an explicit list of what is not finished.

**Keywords**: artificial life; autopoiesis; self-maintenance; substrate independence; persistent agent; identity continuity; governed execution; agent architecture; agent runtime; mechanism integration; artificial general intelligence

## 1. The question I changed

Most work on agents measures outcomes: task success, retrieval accuracy, benchmark scores. These answer "how far can it go", not "what makes it one thing rather than a pile of functions". The second question is prior: an entity that is replaced on every call cannot fail an identity test, because it never had one to pass.

So the question here is: **what makes an artificial system count as alive, and only then, what follows from being alive.**

The answer, stated up front: **intelligence is a consequence of life; a heartbeat is the starting point of evolution.** The direction is one-way: first continue, then become smart. Reversing it — demanding intelligence first and asking afterwards whether the result is still the same entity — is the root error of the current mainstream.

## 2. First cause: continuation is entailed, not decreed

A first cause is usually written as a rule ("a system must continue"). That is a downgrade: rules can be violated, whereas the necessity in question cannot.

Anything that breaks needs work to keep going. That is not a design choice; it is the physical premise. From it, "must continue" is not an obligation added on top — it is what "continuing" means. A system either continues or it does not; there is no third state in which it continues without the work.

The operational test is therefore not "remove the sentence that says must-continue and see whether behaviour changes" (that tests a document). It is: **remove the capacity to reproduce itself — cannot read its own description, cannot write back its trace — and ask whether it is still the same individual.** If it is not, continuation was load-bearing.

## 3. The unit of being alive: one complete loop

Being alive is not a property held continuously; it is an event repeated. One heartbeat equals **one complete loop run end to end**: read what the last round left → construct → judge → dispatch → write back → be readable by the next round.

Three consequences:

1. If the loop is interrupted anywhere, *this* beat did not happen. It is not "a component is broken"; it is that the beat is missing.
2. The loop must return to its starting point. A call that returns a result and stops is not a loop; it never comes back.
3. Because each beat starts a new process using the current code, the beat itself is the version switch. There is no separate deployment step: changing the "heart muscle" changes the next beat.

The standard claim that such a system "needs restarting after a code change" applies to systems that run one fixed process. It does not apply to a system that re-instantiates each beat.

## 4. One line as contract

If every organ invents its own output format, the bus must parse prose, and any reformatting silently breaks the chain. The contract is therefore reduced to a single machine-readable line emitted by each organ. Human-readable output may change freely; the line may not.

This mirrors a general lesson: **a rule that must hold in more than one place can have only one authoritative copy.** When the mapping from exit codes to states existed in three files, two of them were wrong, and in different ways — which is why nobody noticed.

## 5. Judgment lives outside the model; force lives inside it

A language model is a good writer and an unreliable judge: its default is to continue plausibly, not to be correct. Attempts to fix this by training or prompting have failed for a structural reason — the failure mode and the capability come from the same next-token path.

The architectural answer is not to make the writer reliable, but to make the loop independent of the writer being right:

- the criteria live in a versioned specification, not in prose;
- the checks are executed by code, not by the model;
- adversarial probes are run against the checkers themselves (a checker that has never failed is not a checker);
- the last layer is left to a human or to a future layer — it is never claimed to be verified.

This is where the present work differs from governance-oriented systems: those externalize *authority* (who may act, whether an action may execute). Here the externalized object is *continuation* (whether the entity still counts as the same one after it breaks).

## 6. Identity across replacement

Four breakpoints are used as identity tests: swap the machine, remove the plugin, rebuild from backup, swap the model. Each asks the same question: after the replacement, does the system still come up, and does it still judge the same way?

Two of the four have been measured on the running system (plugin removal, rebuild); machine swap and model swap have not. This asymmetry is stated rather than hidden: a test that has not been run cannot support a claim.

The relevant literature evaluates adjacent properties — identity facts and their enactment (PAI-Bench), governed state transitions with scoped authority (the Cognitive Continuity Test), preservation of identity across model, harness and host changes (runtime-independent persistent agents), and the location of control in the model–runtime split (Cartesian agency). None of these evaluates the property at stake here: **whether a broken loop can come back and still be the same loop**, measured on a live heartbeat.

## 7. Four claims and what would refute them

1. **First cause: survival.** Refuted by a carrier that needs no maintenance yet still grows intelligence.
2. **Intelligence is a consequence of life.** Refuted by intelligence preceding survival.
3. **A heartbeat is where evolution starts.** Refuted by a system with no self-driven clock that nevertheless improves against its own past; without a beat there is no reference point, so "better" has no unit.
4. **General problem theory: universal problem, substrate-dependent solution.** Refuted by a solution that cannot state how it would change on another substrate; a theory that only explains itself fails this test.

## 8. Honest limits

- The consciousness layer is unfinished; the memory organ is complete enough to run but not to claim completeness.
- Two of four breakpoints are unverified.
- The self-repair story covers the whole machine (power on implies a beat) but not a single dead organ while the heart still beats.
- The "better or worse" signal is binary (recovered / not recovered) and post hoc; there is no reward signal.
- The claim "no precedent" was withdrawn: the same elements exist in philosophy, life science and agent engineering. What is absent is the chain, and a runnable acceptance test for it.

## 9. Reproducible addresses

- Running system: heartbeat, organ registry, bus contract, immune checks with adversarial probes.
- Repository: https://github.com/raoain/dsh-memory-kit (AGPL-3.0)
- Chinese manuscript and appendices: https://doi.org/10.5281/zenodo.24151620

## References

[1] Lott, M., & Hasselberger, W. Why AGI could not be (just) a tool: goals, life, and general intelligence. Inquiry, 2024. doi:10.1080/0020174X.2024.2436936
[2] Lerchner, A. Artificial intelligence is algorithmic mimicry: why artificial "agents" are not (and won't be) proper agents. arXiv:2307.07515, 2023.
[3] The Cognitive Continuity Test: verifying governed state transitions in persistent AI agents. arXiv:2610.00132, 2026.
[4] Identity is more than recall: a benchmark for persistent identity in deployed AI agents. arXiv:2609.13637, 2026.
[5] Runtime-independent persistent agents: preserving identity, memory, and code across models, harnesses, and servers. arXiv:2609.00546, 2026.
[6] Agent identity evals: measuring agentic identity. arXiv:2507.17257, 2025.
[7] The narrative continuity test. arXiv:2510.24831, 2025.
[8] The situated identity test. arXiv:2609.22195, 2026.
[9] The Cartesian cut in agentic AI. arXiv:2604.07745, 2026.
[10] A control-theoretic foundation for agentic systems. arXiv:2603.10779, 2026.
[11] From cognitive architectures to language agents: a mechanism-level review. arXiv:2607.23942, 2026.
[12] Correct is not governed: provenance integrity in agentic workflows. arXiv:2608.12761, 2026.
[13] From evidence to effect: authority semantics and runtime infrastructure for stateful agents. arXiv:2609.08472, 2026.
[14] Rao, Z. The Ladder of Necessity: what counts as a complete consciousness. Zenodo, 2025. doi:10.5281/zenodo.23987649
[15] Rao, Z. The Guarded Chain. Zenodo, 2024. doi:10.5281/zenodo.23961529
