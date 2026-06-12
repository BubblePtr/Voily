import { readFileSync } from 'node:fs'
import { describe, expect, test } from 'bun:test'

import {
  buildSceneDonutSegments,
  buildSceneSegments,
  getSceneDonutTerminalCapColor,
  sceneDonutRevealHeadRadius,
  sceneDonutRevealMaskLineCap,
  sceneDonutTerminalCapRadius,
  sceneDonutCounterclockwiseRevealPath,
  sceneHourBarDelayStepMs,
} from './DashboardWindow'

describe('buildSceneSegments', () => {
  test('keeps four main scene segments and collapses the rest into Others', () => {
    expect(
      buildSceneSegments([
        { name: 'Claude', pct: 37 },
        { name: 'Cursor', pct: 26 },
        { name: 'Codex', pct: 16 },
        { name: 'Google Chrome', pct: 12 },
        { name: 'Discord', pct: 5 },
        { name: 'Notion', pct: 4 },
      ]),
    ).toEqual([
      { name: 'Claude', pct: 37, color: '#5aa6ff' },
      { name: 'Cursor', pct: 26, color: '#1f86ff' },
      { name: 'Codex', pct: 16, color: '#0b63d6' },
      { name: 'Google Chrome', pct: 12, color: '#0a3f93' },
      { name: 'Others', pct: 9, color: '#0b2a5e' },
    ])
  })
})

describe('buildSceneDonutSegments', () => {
  test('positions final donut colors for a shared reveal animation', () => {
    const segments = buildSceneDonutSegments([
      { name: 'Claude', pct: 37, color: '#5aa6ff' },
      { name: 'Cursor', pct: 26, color: '#1f86ff' },
      { name: 'Codex', pct: 16, color: '#0b63d6' },
      { name: 'Google Chrome', pct: 12, color: '#0a3f93' },
      { name: 'Others', pct: 9, color: '#0b2a5e' },
    ])

    expect(segments.map((segment) => segment.offsetPct)).toEqual([0, 37, 63, 79, 91])
    expect(segments.map((segment) => segment.visiblePct)).toEqual([35.8, 24.8, 14.8, 10.8, 7.8])
    expect(segments.every((segment) => 'animationDelayMs' in segment)).toBe(false)
  })

  test('uses an explicit counterclockwise reveal path', () => {
    expect(sceneDonutCounterclockwiseRevealPath).toBe(
      'M 60 13 A 47 47 0 1 0 60 107 A 47 47 0 1 0 60 13',
    )
  })

  test('uses a flat reveal body with separate rounded moving and terminal caps', () => {
    expect(sceneDonutRevealMaskLineCap).toBe('butt')
    expect(sceneDonutRevealHeadRadius).toBe(8)
    expect(sceneDonutTerminalCapRadius).toBe(5.5)
  })

  test('uses the final segment color for the completed terminal cap', () => {
    const segments = buildSceneSegments([
      { name: 'Claude', pct: 37 },
      { name: 'Cursor', pct: 26 },
      { name: 'Codex', pct: 16 },
      { name: 'Google Chrome', pct: 12 },
      { name: 'Discord', pct: 5 },
      { name: 'Notion', pct: 4 },
    ])

    expect(getSceneDonutTerminalCapColor(segments)).toBe('#0b2a5e')
  })

  test('keeps the terminal cap rounded throughout the reveal animation', () => {
    const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8')
    const keyframeStart = css.indexOf('@keyframes scene-donut-terminal-cap-appear')
    const nextRuleStart = css.indexOf('.scene-donut-center', keyframeStart)
    const terminalCapKeyframe = css.slice(keyframeStart, nextRuleStart)

    expect(terminalCapKeyframe).toContain('8%')
    expect(terminalCapKeyframe).not.toContain('96%')
  })

  test('uses a shared closing-slow easing for donut and hour bars', () => {
    const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8')
    const easingUses = css.match(/var\(--dashboard-closing-ease\)/g) ?? []

    expect(css).toContain('--dashboard-closing-ease: cubic-bezier(0.24, 0.72, 0.22, 1);')
    expect(easingUses.length).toBeGreaterThanOrEqual(5)
    expect(css).not.toContain('cubic-bezier(0.22, 0.78, 0.24, 1)')
    expect(css).not.toContain('cubic-bezier(0.2, 0.82, 0.22, 1)')
  })

  test('matches the app bar cascade delay step', () => {
    expect(sceneHourBarDelayStepMs).toBe(45)
  })
})
