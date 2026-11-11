// core/memsignal.mjs -- 记忆打分的唯一实现：半衰、重要性、命中数、状态权重都从这里来。
//
// Why (2026-11-11 用户): 「建一个统一标志表都归纳起来不就好了」。
// 在这之前，同一个"30 天半衰 x 重要性"在 core/memsearch.mjs 与 core/mem-tier.mjs 各写了一遍：
// 今天数字一样，明天谁改一处就分叉（同族：state->rush 抄三份抄歪）。
// 规则表：core/memsignal.json（改数值改那里，不在这里）；tier 阈值仍在 core/mem-tier.json。
// 判据：一个因子只在一处算；调用方只决定"乘不乘"它。

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

// 2026-11-11 合并进 spec：config lives in core/spec.json -> memory.signal (one single table)
const CFG = (() => {
  try {
    const s = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
    return (s.memory && s.memory.signal) || {}
  } catch { return {} }
})()

export const HALF_LIFE_DAYS = Number(CFG.half_life_days || 30)
export const IMPORTANCE_GAIN = Number(CFG.importance_gain ?? 0.15)
export const IMPORTANCE_CAP = Number(CFG.importance_cap || 4)
export const HITS_GAIN = Number(CFG.hits_gain ?? 0.12)

/** 时间衰减：30 天半衰。 */
export function decay (days) {
  return Math.pow(0.5, Math.max(0, Number(days) || 0) / HALF_LIFE_DAYS)
}

/** 重要性加权：1 + gain * min(importance, cap)。 */
export function importanceBoost (importance) {
  return 1 + IMPORTANCE_GAIN * Math.min(Number(importance || 1), IMPORTANCE_CAP)
}

/** 命中数加权：1 + gain * ln(1 + hits)（被读过才加分，读得越多越慢）。 */
export function hitsBoost (hits) {
  return 1 + HITS_GAIN * Math.log(1 + Number(hits || 0))
}

/** 状态权重：active 1 / stale 0.6 / archived 0（归档即 0，等于不再出现）。 */
export function statusFactor (status) {
  const w = (CFG.status_weight || {})[String(status || 'active')]
  return w === undefined ? 1 : Number(w)
}

// product of the four factors; 0 means "do not use this row"
export function signal (row, now = Date.now(), { useHits = true } = {}) {
  const days = (now - Number(row.updated_at || 0)) / 86400000
  const f = decay(days) * importanceBoost(row.importance) * statusFactor(row.status)
  return useHits ? f * hitsBoost(row.hits) : f
}
