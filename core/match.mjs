// match.mjs -- the ONE implementation of "does this rule want this signal".
//
// Why a separate module (2026-11-09): the matching used to live only inside reflex.mjs, so
// nothing else could ask "would any real signal ever match this rule". The immune table needed
// exactly that, and the obvious shortcut (write the comparison a second time) is the bug we
// already have on record: two copies of one rule start drifting from the day the second exists.
// So the function moved here and both callers import it.
//
// Semantics:
//   - `state` in a rule may be a NAME (pass/warn/fail/unknown); the numbers live in spec.state
//   - any other string field is compared as a string (topic, cell name tags)
//   - everything else is compared numerically
//   - an unknown state name matches nothing: never guess

export function matches(SPEC, when, sig) {
  for (const [k, v] of Object.entries(when)) {
    let want = v
    if (k === 'state' && typeof v === 'string') {
      const found = Object.keys(SPEC.state).find((n) => SPEC.state[n] === v)
      if (found === undefined) return false
      if (Number(sig[k]) !== Number(found)) return false
      continue
    }
    if (typeof v === 'string') {
      if (String(sig[k]) !== v) return false
      continue
    }
    if (Number(sig[k]) !== Number(want)) return false
  }
  return true
}
